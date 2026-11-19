# Emulator tests

These tests apply the module against [AWS Emulator](https://github.com/aws/aws-emulator), a local copy of the AWS APIs. They create, update, and destroy clusters with no AWS account and no cost, and the emulator rejects calls that break AWS API rules.

The module has two test suites:

- `tests/unit` uses the mock provider and runs in seconds. It covers logic inside the module that a plan or a mock apply can show, such as defaults, `for_each` keys, and names.
- `tests/emulator` takes minutes. Each file applies the module and destroys it at the end. `lifecycle.tftest.hcl` also updates it in place.

## Running

```sh
tests/emulator/run.sh
```

The script starts the emulator, runs `terraform test -test-directory=tests/emulator`, and stops the emulator. It uses the `aws-emulator` command when it is on `PATH`. Otherwise it builds `Dockerfile` and runs the emulator in Docker. Extra arguments go to `terraform test`, so one file runs with:

```sh
tests/emulator/run.sh -filter=tests/emulator/lifecycle.tftest.hcl
```

Requirements:

- Terraform 1.13 or later
- Docker, on machines without the Linux package

`lifecycle.tftest.hcl` takes about 3 minutes and `restore.tftest.hcl` about 3.5. Nearly all of that is the AWS provider's fixed 30 second wait before it checks a new cluster or instance.

## CI

`.github/workflows/emulator_checks.yml` runs each test file as its own job. Each job starts emulator v1.0.513 with [`synapsestudios/setup-aws-emulator`](https://github.com/synapsestudios/setup-aws-emulator) and calls `terraform test` directly, without `run.sh`. The `Emulator Checks` job passes only when every file passes. Add a new test file to the job's matrix, or CI won't run it.

## Files

| File                   | Purpose                                                                |
| ---------------------- | ---------------------------------------------------------------------- |
| `lifecycle.tftest.hcl` | Create, add an instance, admit a client security group, destroy        |
| `restore.tftest.hcl`   | Restore from a snapshot                                                |
| `setup/`               | A VPC with two subnets, a parameter group, and a client security group |
| `snapshot_source/`     | A cluster and snapshot for the restore test                            |

## Safety

Each test file sends every AWS service the tests call to the local emulator. It also sets `allowed_account_ids = ["000000000000"]`, the emulator's only account. `emulator_endpoint` has no default, so a file only runs when you pass it with `-var`. `run.sh` and CI both do.
