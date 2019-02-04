// Copyright 2019 The Google Cloud Robotics Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// The robotauth package contains the class for reading and writing the
// robot-id.json file. This file contains the id & private key of a robot
// that's connected to a Cloud project.
package robotauth

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"time"

	"cloud-robotics.googlesource.com/cloud-robotics/pkg/kubeutils"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/jwt"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

const (
	// TODO(ensonic): setup-dev creates a key and stores it, only for the ssh-app to read it
	credentialsFile       = "~/robco/robot-id.json"
	credentialsSecretName = "robot-auth"
)

// Object containing ID, as stored in robot-id.json.
type RobotAuth struct {
	RobotName string `json:"id"`
	ProjectId string `json:"project_id"`
	// Deprecated: Not written anymore and replaced by PublicKeyRegistryId (a
	// string ID which can be determined client-side rather than server-side
	// by the Cloud Iot Registry).
	IotNumId            uint64 `json:"iot_num_id,string,omitempty"`
	PublicKeyRegistryId string `json:"public_key_registry_id"`
	PrivateKey          []byte `json:"private_key"`
	Domain              string `json:"domain"`
}

func filename() string {
	return kubeutils.ExpandUser(credentialsFile)
}

// LoadFromFile loads
func LoadFromFile() (*RobotAuth, error) {
	raw, err := ioutil.ReadFile(filename())
	if err != nil {
		return nil, fmt.Errorf("failed to read %v: %v", credentialsFile, err)
	}

	var robotAuth RobotAuth
	err = json.Unmarshal(raw, &robotAuth)
	if err != nil {
		return nil, fmt.Errorf("failed to parse %v: %v", credentialsFile, err)
	}

	return &robotAuth, nil
}

// Write a newly-chosen ID to disk.
func (r *RobotAuth) StoreInFile() error {
	raw, err := json.Marshal(r)
	if err != nil {
		return fmt.Errorf("failed to serialize ID: %v", err)
	}

	file := filename()
	if err := os.MkdirAll(kubeutils.ExpandUser(filepath.Dir(file)), 0700); err != nil {
		return err
	}

	err = ioutil.WriteFile(file, raw, 0600)
	if err != nil {
		return fmt.Errorf("failed to write %v: %v", credentialsFile, err)
	}

	return nil
}

func LoadFromK8sSecret(clientset *kubernetes.Clientset) (*RobotAuth, error) {
	secrets := clientset.CoreV1().Secrets(corev1.NamespaceDefault)
	robotAuthSecret, err := secrets.Get(credentialsSecretName, metav1.GetOptions{})
	if err != nil {
		return nil, err
	}

	var robotAuth RobotAuth
	if err = json.Unmarshal(robotAuthSecret.Data["json"], &robotAuth); err != nil {
		return nil, err
	}

	return &robotAuth, err
}

func (r *RobotAuth) StoreInK8sSecret(clientset *kubernetes.Clientset) error {
	authJson, err := json.Marshal(r)
	if err != nil {
		return err
	}

	return kubeutils.UpdateSecret(
		clientset,
		credentialsSecretName,
		corev1.SecretTypeOpaque,
		map[string][]byte{
			"json": authJson,
		})
}

// serviceAccountCredentialsFile is the same file format as used by keys
// exported for Google's service account credential files.
type serviceAccountCredentialsFile struct {
	Type         string `json:"type"` // must be service_account
	ClientEmail  string `json:"client_email"`
	ClientId     string `json:"client_id"`
	PrivateKeyID string `json:"private_key_id"`
	PrivateKey   string `json:"private_key"`
	TokenURL     string `json:"token_uri"`
	ProjectID    string `json:"project_id"`
}

func (r *RobotAuth) getTokenEndpoint() string {
	return fmt.Sprintf("https://%s/apis/core.token-vendor/v1/token.oauth2", r.Domain)
}

// Returns the ID by which the robots public key is stored in the cloud.
func (r *RobotAuth) GetPublicKeyRegistryId() string {
	if r.PublicKeyRegistryId != "" {
		return r.PublicKeyRegistryId
	} else {
		// Instances parsed from old JSON files on robots have IotNumId instead of PublicKeyRegistryId
		return fmt.Sprintf("%d", r.IotNumId)
	}
}

// CreateRobotTokenSource creates an OAuth2 token source for the token vendor.
// This token source returns Google Cloud access token minted for the robot-service@
// service account.
func (auth *RobotAuth) CreateRobotTokenSource(ctx context.Context) oauth2.TokenSource {
	c := jwt.Config{
		Email:      auth.GetPublicKeyRegistryId(), // Will be used as "issuer" of the outgoing JWT.
		Expires:    time.Minute * 30,
		PrivateKey: auth.PrivateKey,
		Scopes:     []string{auth.getTokenEndpoint()},
		Subject:    auth.RobotName,
		TokenURL:   auth.getTokenEndpoint(),
	}
	return c.TokenSource(ctx)
}
