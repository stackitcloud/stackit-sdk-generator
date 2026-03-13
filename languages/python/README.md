# STACKIT Python SDK Generator

## Quick Update Guide

| File                               | Action                                  |
|------------------------------------|-----------------------------------------|
| `configuration.mustache`           | do nothing                              |
| `readme.mustache`                  | do nothing                              |
| `pyproject.mustache`               | check dependencies, adjust if necessary |
| `rest.mustache`                    | port changes                            |
| `api.mustache`                     | port changes                            |
| `api_client.mustache`              | port changes                            |
| `model_generic.mustache`           | port changes                            |
| `model_oneof.mustache`             | port changes                            |
| `exceptions.mustache`              | port changes                            |
| `__init__package.mustache`         | port changes                            |
| `README_onlypackage.mustache`      | do nothing, unchanged                   |
| `api_doc.mustache`                 | do nothing, unchanged                   |
| `api_doc_example.mustache`         | do nothing, unchanged                   |
| `api_response.mustache`            | do nothing, unchanged                   |
| `api_test.mustache`                | do nothing, unchanged                   |
| `asyncio`                          | do nothing, unchanged                   |
| `common_README.mustache`           | do nothing, unchanged                   |
| `__init__.mustache`                | do nothing, unchanged                   |
| `__init__api.mustache`             | do nothing, unchanged                   |
| `__init__model.mustache`           | do nothing, unchanged                   |
| `git_push.sh.mustache`             | do nothing, unchanged                   |
| `github-workflow.mustache`         | do nothing, unchanged                   |
| `gitignore.mustache`               | do nothing, unchanged                   |
| `gitlab-ci.mustache`               | do nothing, unchanged                   |
| `model.mustache`                   | do nothing, unchanged                   |
| `model_anyof.mustache`             | do nothing, unchanged                   |
| `model_doc.mustache`               | do nothing, unchanged                   |
| `model_enum.mustache`              | do nothing, unchanged                   |
| `model_test.mustache`              | do nothing, unchanged                   |
| `partial_api.mustache`             | do nothing, unchanged                   |
| `partial_api_args.mustache`        | do nothing, unchanged                   |
| `partial_header.mustache`          | do nothing, unchanged                   |
| `py.typed.mustache`                | do nothing, unchanged                   |
| `python_doc_auth_partial.mustache` | do nothing, unchanged                   |
| `requirements.mustache`            | do nothing, unchanged                   |
| `rest.mustache`                    | do nothing, unchanged                   |
| `setup.mustache`                   | do nothing, unchanged                   |
| `setup_cfg.mustache`               | do nothing, unchanged                   |
| `signing.mustache`                 | do nothing, unchanged                   |
| `test-requirements.mustache`       | do nothing, unchanged                   |
| `tornado`                          | do nothing, unchanged                   |
| `tox.mustache`                     | do nothing, unchanged                   |
| `travis.mustache`                  | do nothing, unchanged                   |
| `exports_api.mustache`             | do nothing, unchanged                   |
| `exports_model.mustache`           | do nothing, unchanged                   |
| `exports_package.mustache`         | do nothing, unchanged                   |


If upstream contains a template, not listed here, adjust the table accordingly.

## Template adjustments

The following templates were customized but don't need to be adjusted when updating the Python SDK generator to a newer
upstream version:

- `configuration.mustache`: This template was entirely overwritten to provide a custom `HostConfiguration`. The
  `Configuration` from `core` is used instead of generating a new one for each service.
- `readme.mustache`: it's the readme
- `pyproject.mustache`: heavily customized to use `uv`, just check the dependencies

The following templates were customized and need to be checked for adjustments when updating the Python SDK generator to
a newer upstream version:

- `rest.mustache`:
    - uses `requests` instead of `urllib3` for making HTTP requests. This is done to use the same library as `core` does.
      `core` uses `requests` because of an ADR: "HTTP Client for Python Core Implementation" (internal link).
    - upstream also configures a `urllib3.PoolManager` for each API client. In `requests` this is done by using
      `requests.Session()` for doing requests. A global pool can be used by setting `custom_http_session` on `Config`.
- `api.mustache`:
    - customized to use `core`'s `Configuration`
- `api_client.mustache`:
    - customized to use `core`'s `Configuration`
    - `update_params_for_auth` and `_apply_auth_params` removed, authentication is done in `core`
- `model_generic.mustache`:
    - contains a temporary workaround for the year 0 issue
- `model_oneof.mustache`:
    - workaround for pattern containing leading and trailing `/`
    - removal of `ValueError` if multiple matches are found
- `exceptions.mustache`:
  - use `requests` instead of `urllib3`
- `__init__package.mustache`:
  - customized imports
