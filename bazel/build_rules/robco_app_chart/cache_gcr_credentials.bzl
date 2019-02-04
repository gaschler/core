def _get_runfile_path(ctx, f):
    """Return the runfiles relative path of f."""
    if ctx.workspace_name:
        return "${RUNFILES}/" + ctx.workspace_name + "/" + f.short_path
    else:
        return "${RUNFILES}/" + f.short_path

def _impl(ctx):
    runfiles = list(ctx.attr._sh_tpl.default_runfiles.files)
    runfiles.append(ctx.attr.target.files_to_run.executable)
    runfiles.extend(list(ctx.attr.target.default_runfiles.files))

    variables = "PYTHON_RUNFILES=\"${RUNFILES}\" "
    ctx.actions.expand_template(
        template = ctx.file._sh_tpl,
        substitutions = {
            "%{gcr_registry}": ctx.attr.gcr_registry,
            "%{command}": variables + _get_runfile_path(ctx, ctx.attr.target.files_to_run.executable),
        },
        output = ctx.outputs.executable,
        is_executable = True,
    )

    return struct(runfiles = ctx.runfiles(files = runfiles))

cache_gcr_credentials = rule(
    attrs = {
        "target": attr.label(
            mandatory = True,
        ),
        "gcr_registry": attr.string(
            default = "",
            doc = "If set, credentials for this GCR registry will be precached",
        ),
        "_sh_tpl": attr.label(
            default = Label("@cloud_robotics//bazel/build_rules/robco_app_chart:cache_gcr_credentials.sh.tpl"),
            allow_single_file = True,
        ),
    },
    executable = True,
    implementation = _impl,
)
"""Cache gcr credentials before running a command.

This rule executes docker-credential-gcloud before running the command, and
replaces the binary with a helper that is safe for concurrent execution. Works
around around https://github.com/bazelbuild/rules_docker/issues/511.

Args:
  target: A target that can be run with "bazel run".
  gcr_registry: string. A GCR Docker registry (gcr.io/myproject).
"""
