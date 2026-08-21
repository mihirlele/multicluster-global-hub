# OLMv1 Validation Report Template

Use this template to create your Jira issue for OCPSTRAT-2268 Phase 2 validation.

---

## Issue Template

**Summary:** OLMv1 Validation - multicluster-global-hub-operator-rh

**Description:**

### Cluster Information

- **OCP Version:** `<from validation output>`
- **Feature Set:** `<TechPreviewNoUpgrade or other>`
- **Test Date:** `<YYYY-MM-DD>`
- **Operator Version Tested:** `<from validation output>`
- **Namespace:** `multicluster-global-hub`

### Installation Result (OCPSTRAT-2268 Step 3)

**Status:** ✅ PASS / ❌ FAIL

**Details:**
```
<Paste output from olmv1_ocp_setup.sh>
```

**Summary:**
- ClusterExtension installed: [ ] Yes [ ] No
- Operator deployment available: [ ] Yes [ ] No
- Installation errors: [ ] None [ ] See details

### Runtime Result (OCPSTRAT-2268 Step 4)

**Status:** ✅ PASS / ❌ FAIL

**Details:**
```
<Paste output from olmv1_ocp_validate.sh>
```

**Test Coverage:**
- [x] Operator reconciles MulticlusterGlobalHub CR
- [x] Manager deployment successful
- [x] Kafka cluster deployed and Ready
- [x] PostgreSQL cluster deployed and Ready
- [ ] Grafana deployment successful (not validated by automated script)
- [x] Overall system status: Running

**Functional Tests Run:**
- [ ] Basic spec/status sync (if managed hubs available)
- [ ] Policy propagation (if applicable)
- [ ] Metrics collection (if applicable)
- [ ] Other: `<describe>`

### Support Commitment

**Will your team support this version if customers install it via OLMv1?**

- [ ] **Yes** - Ready for production with OLMv1
- [ ] **No** - Issues found that block production use
- [ ] **Conditional** - See feedback below

### Additional Feedback

**Issues Found:**
- None / `<Describe any issues, errors, or unexpected behavior>`

**OLMv1-Specific Observations:**
- `<Any differences from OLMv0 behavior>`
- `<Webhook functionality - any issues?>`
- `<OwnNamespace mode - working as expected?>`
- `<OperatorConditions - any warnings/errors from lack of support?>`

**Performance Notes:**
- Installation time: `<duration>`
- Component bring-up time: `<duration>`

**Other Observations:**
- `<Any other relevant information>`

---

## Testing Procedure

### Prerequisites

1. Access to OCP cluster (4.18+ with OLMv1 support)
   - For OCP 4.21+: Use nightly build with TechPreviewNoUpgrade feature set
   - Obtain via clusterbot: `launch 4.21.0-0.nightly aws,techpreview`

2. cluster-admin privileges

3. `oc` CLI installed and configured

### Test Steps

#### 1. Setup

```bash
# Clone the repository
git clone https://github.com/stolostron/multicluster-global-hub.git
cd multicluster-global-hub

# Login to your OCP cluster
oc login <cluster-api-url>

# Run setup script
./test/script/olmv1_ocp_setup.sh
```

**Expected Result:** 
- ClusterExtension shows Installed=True
- Operator deployment is Available

#### 2. Create MulticlusterGlobalHub CR

```bash
# Apply the CR
oc apply -f - <<EOF
apiVersion: operator.open-cluster-management.io/v1alpha4
kind: MulticlusterGlobalHub
metadata:
  name: multiclusterglobalhub
  namespace: multicluster-global-hub
spec:
  availabilityConfig: Basic
  dataLayer:
    kafka:
      storageSize: 10Gi
    postgres:
      retention: 18m
      storageSize: 10Gi
EOF

# Wait for components (5-10 minutes)
watch oc get pods -n multicluster-global-hub
```

**Expected Result:**
- Manager pod Running
- Kafka cluster Ready
- PostgreSQL StatefulSet ready
- Grafana pod Running

#### 3. Runtime Validation

```bash
# Run validation script
./test/script/olmv1_ocp_validate.sh
```

**Expected Result:**
- All 10 validation checks pass
- MulticlusterGlobalHub phase: Running

#### 4. Optional: Functional Testing

If you have managed hub clusters available:

```bash
# Import a managed hub
# <follow standard Global Hub import procedure>

# Verify spec/status sync works
# <verify policies/applications sync>
```

#### 5. Cleanup

```bash
# Remove all resources
./test/script/olmv1_ocp_cleanup.sh
```

---

## Common Issues and Resolutions

### Issue: ClusterExtension shows Installed=False

**Symptoms:**
- ClusterExtension stuck in Pending or Unknown state
- Condition message shows resolution errors

**Resolution:**
1. Check ClusterCatalog is Serving:
   ```bash
   oc get clustercatalog/global-hub -o yaml
   ```

2. Verify package name matches:
   ```bash
   oc get clusterextension/multicluster-global-hub-operator-rh -o yaml | grep packageName
   ```

3. Check catalog contents:
   ```bash
   oc get packages.catalogs.olm.operatorframework.io multicluster-global-hub-operator-rh
   ```

### Issue: Operator pod CrashLoopBackOff

**Symptoms:**
- Operator pod repeatedly crashes
- Logs show webhook-related errors

**Resolution:**
1. Verify SingleOwnNamespaceInstallSupport feature is enabled (OCP 4.21+):
   ```bash
   oc get deploy operator-controller-controller-manager -n openshift-operator-controller \
     -o jsonpath='{.spec.template.spec.containers[0].args}' | grep SingleOwnNamespaceInstallSupport
   ```

2. Check webhook certificates are mounted correctly:
   ```bash
   oc describe pod -n multicluster-global-hub -l app.kubernetes.io/name=multicluster-global-hub-operator
   ```

### Issue: Components not deploying

**Symptoms:**
- MulticlusterGlobalHub CR created but no manager/kafka/postgres pods

**Resolution:**
1. Check operator logs:
   ```bash
   oc logs -n multicluster-global-hub -l app.kubernetes.io/name=multicluster-global-hub-operator --tail=200
   ```

2. Verify ImageDigestMirrorSet is applied:
   ```bash
   oc get imagedigestmirrorset/global-hub-mirror-set
   ```

3. Check MachineConfigPool status (may need time to update):
   ```bash
   oc get mcp
   ```

---

## Links

- **OCPSTRAT-2268:** https://issues.redhat.com/browse/OCPSTRAT-2268
- **Phase 2 Doc:** Verifying Published Content with OLMv1
- **OLMv1 Docs:** https://docs.openshift.com/container-platform/latest/operators/olm_v1/olmv1-installing-an-operator-from-a-catalog.html
- **Global Hub Docs:** https://github.com/stolostron/multicluster-global-hub/blob/main/doc/README.md
