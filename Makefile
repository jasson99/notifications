# This file is licensed under the Affero General Public License version 3 or
# later. See the COPYING file.
# @author Ilja Neumann <ineumann@owncloud.com>

COMPOSER_BIN := $(shell command -v composer 2> /dev/null)
ifndef COMPOSER_BIN
    $(error composer is not available on your system, please install composer)
endif

app_name=$(notdir $(CURDIR))
project_directory=$(CURDIR)/../$(app_name)
build_tools_directory=$(CURDIR)/build/tools
source_build_directory=$(CURDIR)/build/artifacts/source
source_package_name=$(source_build_directory)/$(app_name)
appstore_build_directory=$(CURDIR)/build/artifacts/appstore
appstore_package_name=$(appstore_build_directory)/$(app_name)
npm=$(shell which npm 2> /dev/null)

acceptance_test_deps=vendor-bin/behat/vendor

occ=$(CURDIR)/../../occ
private_key=$(HOME)/.owncloud/certificates/$(app_name).key
certificate=$(HOME)/.owncloud/certificates/$(app_name).crt
sign=php -f $(occ) integrity:sign-app --privateKey="$(private_key)" --certificate="$(certificate)"
sign_skip_msg="Skipping signing, either no key and certificate found in $(private_key) and $(certificate) or occ can not be found at $(occ)"
ifneq (,$(wildcard $(private_key)))
ifneq (,$(wildcard $(certificate)))
ifneq (,$(wildcard $(occ)))
	CAN_SIGN=true
endif
endif
endif

# bin file definitions
PHPUNIT=php -d zend.enable_gc=0  "$(PWD)/../../lib/composer/bin/phpunit"
PHPUNITDBG=phpdbg -qrr -d memory_limit=4096M -d zend.enable_gc=0 "$(PWD)/../../lib/composer/bin/phpunit"
PHP_CS_FIXER=php -d zend.enable_gc=0 vendor-bin/owncloud-codestyle/vendor/bin/php-cs-fixer
PHP_CODESNIFFER=vendor-bin/php_codesniffer/vendor/bin/phpcs
PHAN=php -d zend.enable_gc=0 vendor-bin/phan/vendor/bin/phan
PHPSTAN=php -d zend.enable_gc=0 vendor-bin/phpstan/vendor/bin/phpstan
BEHAT_BIN=vendor-bin/behat/vendor/bin/behat

.DEFAULT_GOAL := help

# start with displaying help
help: ## Show this help message
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//' | sed -e 's/  */ /' | column -t -s :

# Removes the appstore build
.PHONY: clean
clean: ## Removes the appstore build
clean: clean-deps
	rm -rf ./build/artifacts

.PHONY: clean-deps
clean-deps:
	rm -Rf vendor
	rm -Rf vendor-bin/**/vendor vendor-bin/**/composer.lock

# Builds the source and appstore package
.PHONY: dist
dist: ## Builds the source and appstore package
	make source
	make appstore

# Builds the source package
.PHONY: source
source: ## Builds the source package
	rm -rf $(source_build_directory)
	mkdir -p $(source_build_directory)
	tar --format=gnu --owner=nobody --group=nogroup -cvzf $(source_package_name).tar.gz \
	--exclude-vcs \
	--exclude="../$(app_name)/build" \
	--exclude="../$(app_name)/js/node_modules" \
	--exclude="../$(app_name)/node_modules" \
	--exclude="../$(app_name)/*.log" \
	--exclude="../$(app_name)/js/*.log" \
	../$(app_name)

# Builds the source package for the app store, ignores php and js tests
.PHONY: appstore
appstore: ## Builds the source package for the app store
	rm -rf $(appstore_build_directory)
	mkdir -p $(appstore_package_name)
	cp --parents -r \
	appinfo \
	css \
	img \
	js \
	l10n \
	lib \
	templates \
	README.md \
	CHANGELOG.md \
	COPYING \
	$(appstore_package_name)
	rm -R $(appstore_package_name)/l10n/.tx

ifdef CAN_SIGN
	$(sign) --path="$(appstore_package_name)"
else
	@echo $(sign_skip_msg)
endif
	tar --format=gnu --owner=nobody --group=nogroup -czf $(appstore_package_name).tar.gz -C $(appstore_package_name)/../ $(app_name)

##------------
## Tests
##------------

.PHONY: test-php-codecheck
test-php-codecheck: ## Test php codecheck
	$(occ) app:check-code $(app_name) -c private -c strong-comparison
	$(occ) app:check-code $(app_name) -c deprecation

.PHONY: test-php-style
test-php-style: ## Run php-cs-fixer and check owncloud code-style
test-php-style: vendor-bin/owncloud-codestyle/vendor vendor-bin/php_codesniffer/vendor
	$(PHP_CS_FIXER) fix -v --diff --diff-format udiff --allow-risky yes --dry-run
	$(PHP_CODESNIFFER) --runtime-set ignore_warnings_on_exit --standard=phpcs.xml tests/acceptance

.PHONY: test-php-style-fix
test-php-style-fix: ## Run php-cs-fixer and fix code style issues
test-php-style-fix: vendor-bin/owncloud-codestyle/vendor
	$(PHP_CS_FIXER) fix -v --diff --diff-format udiff --allow-risky yes

.PHONY: test-php-phan
test-php-phan: ## Run phan
test-php-phan: vendor-bin/phan/vendor
	$(PHAN) --config-file .phan/config.php --require-config-exists

.PHONY: test-php-phpstan
test-php-phpstan: ## Run phpstan
test-php-phpstan: vendor-bin/phpstan/vendor
	$(PHPSTAN) analyse --memory-limit=4G --configuration=./phpstan.neon --no-progress --level=5 appinfo lib

.PHONY: test-php-unit
test-php-unit: ## Run php unit tests
	$(PHPUNIT) --configuration ./phpunit.xml --testsuite unit

.PHONY: test-php-unit-dbg
test-php-unit-dbg: ## Run php unit tests with dbg
	$(PHPUNITDBG) --configuration ./phpunit.xml --testsuite unit

.PHONY: test-acceptance-api
test-acceptance-api: ## Run API acceptance tests
test-acceptance-api: $(acceptance_test_deps)
	BEHAT_BIN=$(BEHAT_BIN) ../../tests/acceptance/run.sh --remote --type api

.PHONY: test-acceptance-cli
test-acceptance-cli: ## Run CLI acceptance tests
test-acceptance-cli: $(acceptance_test_deps)
	BEHAT_BIN=$(BEHAT_BIN) ../../tests/acceptance/run.sh --remote --type cli

.PHONY: test-acceptance-webui
test-acceptance-webui: ## Run webUI acceptance tests
test-acceptance-webui: $(acceptance_test_deps)
	BEHAT_BIN=$(BEHAT_BIN) ../../tests/acceptance/run.sh --remote --type webUI

#
# Dependency management
#--------------------------------------

composer.lock: composer.json
	@echo composer.lock is not up to date.

vendor: composer.lock
	composer install --no-dev

vendor/bamarni/composer-bin-plugin: composer.lock
	composer install

vendor-bin/owncloud-codestyle/vendor: vendor/bamarni/composer-bin-plugin vendor-bin/owncloud-codestyle/composer.lock
	composer bin owncloud-codestyle install --no-progress

vendor-bin/owncloud-codestyle/composer.lock: vendor-bin/owncloud-codestyle/composer.json
	@echo owncloud-codestyle composer.lock is not up to date.

vendor-bin/php_codesniffer/vendor: vendor/bamarni/composer-bin-plugin vendor-bin/php_codesniffer/composer.lock
	composer bin php_codesniffer install --no-progress

vendor-bin/php_codesniffer/composer.lock: vendor-bin/php_codesniffer/composer.json
	@echo php_codesniffer composer.lock is not up to date.

vendor-bin/phan/vendor: vendor/bamarni/composer-bin-plugin vendor-bin/phan/composer.lock
	composer bin phan install --no-progress

vendor-bin/phan/composer.lock: vendor-bin/phan/composer.json
	@echo phan composer.lock is not up to date.

vendor-bin/phpstan/vendor: vendor/bamarni/composer-bin-plugin vendor-bin/phpstan/composer.lock
	composer bin phpstan install --no-progress

vendor-bin/phpstan/composer.lock: vendor-bin/phpstan/composer.json
	@echo phpstan composer.lock is not up to date.

vendor-bin/behat/vendor: vendor/bamarni/composer-bin-plugin vendor-bin/behat/composer.lock
	composer bin behat install --no-progress

vendor-bin/behat/composer.lock: vendor-bin/behat/composer.json
	@echo behat composer.lock is not up to date.
