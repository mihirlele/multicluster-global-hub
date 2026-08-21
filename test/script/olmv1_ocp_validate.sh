#!/bin/bash
# OLMv1 Production Validation for OCP clusters
# Validates operator runtime behavior per OCPSTRAT-2268 requirements

set -euo pipefail

GH_NAMESPACE="${GH_NAMESPACE:-multicluster-global-hub}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALLATION_FAILED=0
RUNTIME_FAILED=0

fail_installation() {
  echo -e "${RED}INSTALLATION VALIDATION FAILED: $1${NC}"
  INSTALLATION_FAILED=1
}

fail_runtime() {
  echo -e "${RED}RUNTIME VALIDATION FAILED: $1${NC}"
  RUNTIME_FAILED=1
}

echo -e "${YELLOW}=== OLMv1 Production Validation ===${NC}"
echo ""

# Gather cluster info for reporting
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
FEATURE_SET=$(oc get featuregate cluster -o jsonpath='{.spec.featureSet}' 2>/dev/null || echo "unknown")

echo "Cluster Information:"
echo "  OCP Version: $OCP_VERSION"
echo "  Feature Set: $FEATURE_SET"
echo "  Namespace: $GH_NAMESPACE"
echo ""

# ── Phase 2 Requirement: Installation Validation (Step 3) ───────────────────
echo -e "${YELLOW}=== Installation Validation (OCPSTRAT-2268 Step 3) ===${NC}"

# 1. Verify OLMv1 components
echo -e "${YELLOW}[1/10] Checking OLMv1 system components...${NC}"
if oc get deploy -n openshift-catalogd &>/dev/null && \
   oc get deploy -n openshift-operator-controller &>/dev/null; then
  echo -e "${GREEN}  ✓ OLMv1 system components present${NC}"
else
  fail_installation "OLMv1 system components missing"
fi

# 2. Verify ClusterCatalog
echo -e "${YELLOW}[2/10] Checking ClusterCatalog...${NC}"
CATALOG_STATUS=$(oc get clustercatalog/global-hub \
  -o jsonpath='{.status.conditions[?(@.type=="Serving")].status}' 2>/dev/null || echo "false")
if [[ "$CATALOG_STATUS" == "True" ]]; then
  echo -e "${GREEN}  ✓ ClusterCatalog is Serving${NC}"
else
  fail_installation "ClusterCatalog not Serving"
fi

# 3. Verify ServiceAccount exists
echo -e "${YELLOW}[3/10] Checking ServiceAccount...${NC}"
if oc get sa/multicluster-global-hub-operator-rh-installer -n "$GH_NAMESPACE" &>/dev/null; then
  echo -e "${GREEN}  ✓ ServiceAccount exists${NC}"
else
  fail_installation "ServiceAccount not found"
fi

# 4. Verify ClusterRoleBinding exists
echo -e "${YELLOW}[4/10] Checking ClusterRoleBinding...${NC}"
if oc get clusterrolebinding/multicluster-global-hub-operator-rh-installer-binding &>/dev/null; then
  echo -e "${GREEN}  ✓ ClusterRoleBinding exists${NC}"
else
  fail_installation "ClusterRoleBinding not found"
fi

# 5. Verify ClusterExtension installed successfully
echo -e "${YELLOW}[5/10] Checking ClusterExtension installation...${NC}"
CE_STATUS=$(oc get clusterextension/multicluster-global-hub-operator-rh \
  -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "false")
if [[ "$CE_STATUS" == "True" ]]; then
  echo -e "${GREEN}  ✓ ClusterExtension Installed=True${NC}"

  # Get installed version
  INSTALLED_VERSION=$(oc get clusterextension/multicluster-global-hub-operator-rh \
    -o jsonpath='{.status.install.bundle.version}' 2>/dev/null || echo "unknown")
  echo "    Installed version: $INSTALLED_VERSION"
else
  fail_installation "ClusterExtension not Installed"
  echo "    Status conditions:"
  oc get clusterextension/multicluster-global-hub-operator-rh -o jsonpath='{.status.conditions}' | jq '.'
fi

# 6. Verify operator deployment
echo -e "${YELLOW}[6/10] Checking operator deployment...${NC}"
if oc wait deploy/multicluster-global-hub-operator -n "$GH_NAMESPACE" \
     --for=condition=Available=True --timeout=60s &>/dev/null; then
  echo -e "${GREEN}  ✓ Operator deployment is Available${NC}"

  REPLICAS=$(oc get deploy/multicluster-global-hub-operator -n "$GH_NAMESPACE" \
    -o jsonpath='{.status.availableReplicas}')
  echo "    Available replicas: $REPLICAS"
else
  fail_installation "Operator deployment not Available"
fi

echo ""
echo -e "${GREEN}=== Installation Validation: $([ $INSTALLATION_FAILED -eq 0 ] && echo PASS || echo FAIL) ===${NC}"
echo ""

# ── Phase 2 Requirement: Runtime Validation (Step 4) ────────────────────────
echo -e "${YELLOW}=== Runtime Validation (OCPSTRAT-2268 Step 4) ===${NC}"
echo "Testing operator runtime behavior with MulticlusterGlobalHub CR..."
echo ""

# Check if MCGH CR exists
if ! oc get mcgh -n "$GH_NAMESPACE" &>/dev/null; then
  echo -e "${RED}ERROR: No MulticlusterGlobalHub CR found.${NC}"
  echo "Runtime validation requires a MulticlusterGlobalHub instance."
  echo ""
  echo "To deploy one, run:"
  echo ""
  echo "  oc apply -f - <<EOF"
  echo "  apiVersion: operator.open-cluster-management.io/v1alpha4"
  echo "  kind: MulticlusterGlobalHub"
  echo "  metadata:"
  echo "    name: multiclusterglobalhub"
  echo "    namespace: ${GH_NAMESPACE}"
  echo "  spec:"
  echo "    availabilityConfig: Basic"
  echo "    dataLayer:"
  echo "      kafka:"
  echo "        storageSize: 10Gi"
  echo "      postgres:"
  echo "        retention: 18m"
  echo "        storageSize: 10Gi"
  echo "  EOF"
  echo ""
  echo "Then re-run this script."
  fail_runtime "MulticlusterGlobalHub CR not found"
  RUNTIME_FAILED=1
  echo ""
  echo "**Installation Result (Step 3):**"
  if [[ $INSTALLATION_FAILED -eq 0 ]]; then
    echo "- Status: ✅ PASS"
  else
    echo "- Status: ❌ FAIL"
  fi
  echo ""
  echo "**Runtime Result (Step 4):**"
  echo "- Status: ❌ FAIL - MulticlusterGlobalHub CR required but not found"
  exit 1
fi

# 7. Validate manager deployment
echo -e "${YELLOW}[7/10] Checking manager deployment...${NC}"
if oc wait deploy/multicluster-global-hub-manager -n "$GH_NAMESPACE" \
     --for=condition=Available=True --timeout=300s &>/dev/null; then
  echo -e "${GREEN}  ✓ Manager deployment is Available${NC}"
else
  fail_runtime "Manager deployment not Available"
fi

# 8. Validate Kafka
echo -e "${YELLOW}[8/10] Checking Kafka cluster...${NC}"
if oc wait kafka -n "$GH_NAMESPACE" --all \
     --for=condition=Ready=True --timeout=300s &>/dev/null; then
  echo -e "${GREEN}  ✓ Kafka cluster is Ready${NC}"
else
  fail_runtime "Kafka cluster not Ready"
fi

# 9. Validate PostgreSQL
echo -e "${YELLOW}[9/10] Checking PostgreSQL cluster...${NC}"
# Determine expected replica count from availabilityConfig
AVAILABILITY_CONFIG=$(oc get mcgh -n "$GH_NAMESPACE" -o jsonpath='{.items[0].spec.availabilityConfig}' 2>/dev/null || echo "Basic")
if [[ "$AVAILABILITY_CONFIG" == "High" ]]; then
  EXPECTED_REPLICAS=3
else
  EXPECTED_REPLICAS=1
fi

if oc wait statefulset -n "$GH_NAMESPACE" \
     -l postgres-operator.crunchydata.com/cluster \
     --for=jsonpath="{.status.readyReplicas}"=$EXPECTED_REPLICAS --timeout=300s &>/dev/null; then
  echo -e "${GREEN}  ✓ PostgreSQL cluster is Ready ($EXPECTED_REPLICAS replicas)${NC}"
else
  fail_runtime "PostgreSQL cluster not Ready (expected $EXPECTED_REPLICAS replicas)"
fi

# 10. Validate overall MCGH status
echo -e "${YELLOW}[10/10] Checking MulticlusterGlobalHub status...${NC}"

# Wait for Running status with timeout
TIMEOUT=300
ELAPSED=0
MCGH_PHASE=""

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  MCGH_PHASE=$(oc get mcgh -n "$GH_NAMESPACE" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "unknown")

  if [[ "$MCGH_PHASE" == "Running" ]]; then
    echo -e "${GREEN}  ✓ MulticlusterGlobalHub phase: Running${NC}"
    break
  elif [[ "$MCGH_PHASE" == "Progressing" ]] || [[ "$MCGH_PHASE" == "" ]]; then
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  else
    # Unexpected phase
    fail_runtime "MulticlusterGlobalHub phase: $MCGH_PHASE (expected Running)"
    break
  fi
done

# If we timed out waiting for Running
if [[ $ELAPSED -ge $TIMEOUT ]] && [[ "$MCGH_PHASE" != "Running" ]]; then
  fail_runtime "MulticlusterGlobalHub did not reach Running state within ${TIMEOUT}s (current: $MCGH_PHASE)"
fi

echo ""
echo -e "${GREEN}=== Runtime Validation: $([ $RUNTIME_FAILED -eq 0 ] && echo PASS || echo FAIL) ===${NC}"
echo ""

# ── Validation Summary for Jira Issue ───────────────────────────────────────
echo -e "${YELLOW}=== Validation Summary ===${NC}"
echo ""
echo "Report the following in your Jira issue (link to OCPSTRAT-2268):"
echo ""
echo "**Cluster Information:**"
echo "- OCP Version: $OCP_VERSION"
echo "- Feature Set: $FEATURE_SET"
echo "- Operator Namespace: $GH_NAMESPACE"
echo ""
echo "**Installation Result (Step 3):**"
if [[ $INSTALLATION_FAILED -eq 0 ]]; then
  echo "- Status: ✅ PASS"
  echo "- ClusterExtension installed successfully"
  echo "- Version: $INSTALLED_VERSION"
else
  echo "- Status: ❌ FAIL"
  echo "- See validation failures above"
fi
echo ""
echo "**Runtime Result (Step 4):**"
if [[ $RUNTIME_FAILED -eq 0 ]]; then
  echo "- Status: ✅ PASS"
  echo "- All components deployed and healthy"
  echo "- Manager, Kafka, PostgreSQL operational"
  echo "- MulticlusterGlobalHub phase: $MCGH_PHASE"
else
  echo "- Status: ❌ FAIL"
  echo "- See validation failures above"
fi
echo ""
echo "**Support Commitment:**"
echo "Will your team support this version if customers install it via OLMv1?"
echo "[ ] Yes - Ready for production"
echo "[ ] No - Issues found (see feedback below)"
echo ""
echo "**Additional Feedback:**"
echo "(Describe any issues, warnings, or observations)"
echo ""

# Exit with failure if any validations failed
if [[ $INSTALLATION_FAILED -ne 0 ]] || [[ $RUNTIME_FAILED -ne 0 ]]; then
  echo -e "${RED}One or more validations failed. See details above.${NC}"
  exit 1
fi

echo -e "${GREEN}All validations passed! ✅${NC}"
