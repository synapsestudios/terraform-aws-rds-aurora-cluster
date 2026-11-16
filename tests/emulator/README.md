# Emulator tests

These tests apply the module against [AWS Emulator](https://github.com/aws/aws-emulator), a local copy of the AWS APIs. They create, update, and destroy real-looking clusters with no AWS account and no cost.

## Running

```sh
tests/emulator/run.sh
```

The script starts the emulator, runs `terraform test -test-directory=tests/emulator`, and stops the emulator. It uses the `aws-emulator` command when it is on `PATH`. Otherwise it builds `Dockerfile` and runs the emulator in Docker. Extra arguments go to `terraform test`.

Requirements:

- Terraform 1.13 or later
- Python 3
- Docker, on machines without the Linux package

A full run takes about nine minutes. Most of that is the AWS provider's fixed 30 second wait before it checks a new cluster or instance.

## Files

| File                      | Purpose                                                               |
| ------------------------- | --------------------------------------------------------------------- |
| `lifecycle.tftest.hcl`    | Create, add an instance, admit a client security group, destroy       |
| `restore.tftest.hcl`      | Restore from a snapshot                                               |
| `contract.tftest.hcl`     | Checks that the mock overrides in `tests/unit/` match the emulator    |
| `setup/`                  | Default VPC lookup, a parameter group, and a client security group    |
| `snapshot_source/`        | A cluster and snapshot for the restore test                           |
| `proxy.py`                | Pass-through proxy with one workaround                                |

## Workarounds

Two emulator bugs block the module. Remove each workaround once its issue is fixed.

- [aws/aws-emulator#46](https://github.com/aws/aws-emulator/issues/46). `aws_security_group` fails in any VPC other than the default one. The tests use the default VPC. The emulator also leaves the allow-all egress rule in place, which AWS removes.
- [aws/aws-emulator#349](https://github.com/aws/aws-emulator/issues/349). Every read of `aws_rds_cluster` fails. `proxy.py` answers that one call with an empty list.

## Safety

Each test file points every provider endpoint at the local proxy and sets `allowed_account_ids = ["000000000000"]`, the emulator's only account. `emulator_endpoint` has no default, so the files don't run without `run.sh`.
