################################################################################
# 変数
################################################################################
STACK_NAME := poc-stack

################################################################################
# マクロ
################################################################################
define get-ubuntu-latest-image-id
aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64*" --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' --output text
endef

define get-vpc-id
aws cloudformation describe-stack-resource --stack-name $(STACK_NAME) --logical-resource-id Vpc --query 'StackResourceDetail.PhysicalResourceId' --output text
endef

define get-default-security-group-id
aws ec2 describe-security-groups --filters Name=vpc-id,Values=$(VPC_ID) Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text
endef

define get-ec2-id
aws cloudformation describe-stack-resource --stack-name $(STACK_NAME) --logical-resource-id Ec2Instance --query 'StackResourceDetail.PhysicalResourceId' --output text
endef

################################################################################
# タスク
################################################################################
.PHONY: up
up: ## CFnスタックをデプロイ
	$(eval IMAGE_ID := $(shell $(call get-ubuntu-latest-image-id)))
	rain deploy --yes main.yaml $(STACK_NAME) --params Ec2ImageId=$(IMAGE_ID)
	make remove-rules-from-default-security-group

.PHONY: down
down: ## CFnスタックを削除
	rain rm --yes $(STACK_NAME)

.PHONY: logs
logs: ## CFnスタックのログを一覧
	rain logs $(STACK_NAME)

.PHONY: tree
tree: ## リソースをtree状にして見せる
	rain tree main.yaml

.PHONY: fmt
fmt: ## CFnのformat
	rain fmt --write ./*.yaml

.PHONY: remove-rules-from-default-security-group
remove-rules-from-default-security-group: ## CFnで作成したVPCのデフォルトセキュリティグループからルールの削除
	$(eval VPC_ID := $(shell $(call get-vpc-id)))
	$(eval DEFAULT_SECURITY_GROUP_ID := $(shell $(call get-default-security-group-id)))
	aws ec2 describe-security-groups --group-id $(DEFAULT_SECURITY_GROUP_ID) \
		| jq --raw-output --compact-output '.SecurityGroups[].IpPermissions' \
		| awk '$$0!="[]"' \
		| xargs --delimiter "\n" -I {ip-permissions} aws ec2 revoke-security-group-ingress --group-id $(DEFAULT_SECURITY_GROUP_ID) --ip-permissions '{ip-permissions}'
	aws ec2 describe-security-groups --group-id $(DEFAULT_SECURITY_GROUP_ID) \
		| jq --raw-output --compact-output '.SecurityGroups[].IpPermissionsEgress' \
		| awk '$$0!="[]"' \
		| xargs --delimiter "\n" -I {ip-permissions-egress} aws ec2 revoke-security-group-egress --group-id $(DEFAULT_SECURITY_GROUP_ID) --ip-permissions '{ip-permissions-egress}'

.PHONY: ssm-session
ssm-session: ## CFnで作成したEC2へssm session managerでつなぐ
	$(eval EC2_ID := $(shell $(call get-ec2-id)))
	aws ssm start-session --target $(EC2_ID)

################################################################################
# Util-macro
################################################################################
# Makefileの中身を抽出してhelpとして1行で出す
# $(1): Makefile名
define help
  grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(1) \
  | grep --invert-match "## non-help" \
  | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
endef

################################################################################
# Util-task
################################################################################
.PHONY: help
help: ## Make タスク一覧
	@echo '######################################################################'
	@echo '# Makeタスク一覧'
	@echo '# $$ make XXX'
	@echo '# or'
	@echo '# $$ make XXX --dry-run'
	@echo '######################################################################'
	@echo $(MAKEFILE_LIST) \
	| tr ' ' '\n' \
	| xargs -I {included-makefile} $(call help,{included-makefile})
