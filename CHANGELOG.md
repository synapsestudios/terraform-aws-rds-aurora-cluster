# Changelog

## [4.0.0](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/compare/v3.2.0...v4.0.0) (2026-11-17)


### ⚠ BREAKING CHANGES

* root_credentials.password is now the password alone. Callers that parse it as JSON must read the value directly.
* stop admitting the whole VPC to the database ([#20](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/issues/20))

### Features

* stop admitting the whole VPC to the database ([#20](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/issues/20)) ([a2fbbf5](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/commit/a2fbbf5586cb59158003ce99caad30783c04804a)), closes [#19](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/issues/19)


### Bug Fixes

* give each final snapshot a unique name ([#27](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/issues/27)) ([3216e3a](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/commit/3216e3a73e7c7e093540265563d734c74f066fe2))
* return only the password from root_credentials.password ([#28](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/issues/28)) ([8db670c](https://github.com/synapsestudios/terraform-aws-rds-aurora-cluster/commit/8db670c2766eb8139680d5c91be7696d6faa5b75))
