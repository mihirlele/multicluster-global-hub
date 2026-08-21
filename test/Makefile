
e2e-dep: 
	./test/script/e2e_dep.sh

e2e-setup: tidy vendor e2e-dep
	./test/script/e2e_setup.sh

kessel-e2e-setup:
	./test/script/kessel_e2e_setup.sh

kessel-e2e-run: tidy vendor
	./test/script/kessel_e2e_run.sh

e2e-cleanup:
	./test/script/e2e_cleanup.sh

GLOBAL_HUB_KUBECONFIG := test/script/config/global-hub

e2e-test-all: tidy vendor
	sh ./test/script/e2e_run.sh -f "e2e-test-localpolicy,e2e-tests-backup,e2e-test-grafana,e2e-test-local-agent" -v $(VERBOSE)
	sh ./test/script/e2e_run.sh -f "e2e-test-prune" -v $(VERBOSE)
	sh ./test/script/e2e_clean_globalhub.sh
	sh ./test/script/e2e_run_byo.sh -v $(VERBOSE)
	sh ./test/script/e2e_run.sh -f "e2e-test-migration" -v $(VERBOSE)
	sh ./test/script/e2e_run.sh -f "e2e-test-hubha" -v $(VERBOSE)
	sh ./test/script/e2e_run.sh -f "e2e-test-transport-identity" -v $(VERBOSE)
	sh ./test/script/e2e_run.sh -f "e2e-test-transport-migration-topic" -v $(VERBOSE)

e2e-test-cluster e2e-test-local-agent e2e-test-localpolicy e2e-test-grafana e2e-test-migration e2e-test-hubha e2e-test-transport-identity e2e-test-transport-migration-topic: tidy vendor
	./test/script/e2e_run.sh -f $@ -v $(VERBOSE)

e2e-prow-tests: 
	./test/script/e2e_prow.sh

e2e-log/operator:
	./test/script/e2e_log.sh

e2e-log/manager:
	@COMPONENT=multicluster-global-hub-manager ./test/script/e2e_log.sh

e2e-log/grafana:
	@COMPONENT=multicluster-global-hub-grafana ./test/script/e2e_log.sh

e2e-log/agent:
	@export CLUSTER_NAME=hub1 COMPONENT=multicluster-global-hub-agent NAMESPACE=multicluster-global-hub-agent && ./test/script/e2e_log.sh
	@export CLUSTER_NAME=hub2 COMPONENT=multicluster-global-hub-agent NAMESPACE=multicluster-global-hub-agent && ./test/script/e2e_log.sh
	@export CLUSTER_NAME=global-hub COMPONENT=multicluster-global-hub-agent && ./test/script/e2e_log.sh

integration-test: setup_envtest
	KUBEBUILDER_ASSETS="$(shell ${TMP_BIN}/setup-envtest use --use-env -p path)" ${GO_TEST} `go list ./test/integration/...`

integration-test/agent: setup_envtest
	KUBEBUILDER_ASSETS="$(shell ${TMP_BIN}/setup-envtest use --use-env -p path)" ${GO_TEST} `go list ./test/integration/agent/...`

integration-test/manager: setup_envtest
	KUBEBUILDER_ASSETS="$(shell ${TMP_BIN}/setup-envtest use --use-env -p path)" ${GO_TEST} `go list ./test/integration/manager/...`

integration-test/operator: setup_envtest
	KUBEBUILDER_ASSETS="$(shell ${TMP_BIN}/setup-envtest use --use-env -p path)" ${GO_TEST} `go list ./test/integration/operator/...`

##@ OLMv1 Validation

.PHONY: olmv1-ocp-setup
olmv1-ocp-setup: ## Setup Global Hub operator via OLMv1 on OCP cluster
	@echo "Setting up OLMv1 installation on connected OCP cluster..."
	@chmod +x ./test/script/olmv1_ocp_setup.sh
	./test/script/olmv1_ocp_setup.sh

.PHONY: olmv1-ocp-validate
olmv1-ocp-validate: ## Validate OLMv1 installation and runtime behavior (OCPSTRAT-2268)
	@echo "Running OLMv1 validation..."
	@chmod +x ./test/script/olmv1_ocp_validate.sh
	./test/script/olmv1_ocp_validate.sh

.PHONY: olmv1-ocp-cleanup
olmv1-ocp-cleanup: ## Cleanup OLMv1 installation from OCP cluster
	@echo "Cleaning up OLMv1 resources..."
	@chmod +x ./test/script/olmv1_ocp_cleanup.sh
	./test/script/olmv1_ocp_cleanup.sh

.PHONY: olmv1-ocp-test-all
olmv1-ocp-test-all: olmv1-ocp-setup olmv1-ocp-validate ## Run complete OLMv1 validation workflow
	@echo "OLMv1 validation workflow complete"
	@echo "Next: Create Jira issue linked to OCPSTRAT-2268 with results"
	@echo "Template: test/docs/olmv1-validation-report.md"
