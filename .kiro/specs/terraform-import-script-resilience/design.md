# Terraform Import Script Resilience Bugfix Design

## Overview

The import script fails prematurely when kubectl cleanup commands encounter errors, preventing critical Grafana resource imports from executing. This causes terraform apply to attempt creating existing Grafana resources, resulting in 409 conflict errors. The fix involves replacing `set -euo pipefail` with selective error handling that allows the script to continue through failures while still logging errors for debugging. The script will maintain a failure tracking mechanism to report issues without blocking execution, ensuring all import operations complete regardless of individual command failures.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when any kubectl command in the cleanup section fails, causing immediate script exit
- **Property (P)**: The desired behavior - script continues executing all import operations even when individual commands fail, logging errors without exiting
- **Preservation**: Existing import functionality, reporting, and success cases that must remain unchanged by the fix
- **cleanup_conflicting_resources**: Function in `import-existing-resources.sh` that removes cluster-scoped resources owned by other namespaces
- **import_resource**: Helper function that attempts terraform import and updates the JSON report
- **set -euo pipefail**: Bash strict mode that causes script to exit immediately on any command failure
- **Grafana resource imports**: The section of the script that imports existing Grafana teams and datasources into Terraform state

## Bug Details

### Fault Condition

The bug manifests when any kubectl command in the cleanup section fails (e.g., attempting to delete a non-existent clusterrole, permission denied, timeout). The script is using `set -euo pipefail` which causes immediate exit on any command failure, preventing subsequent import operations from executing.

**Formal Specification:**
```
FUNCTION isBugCondition(scriptExecution)
  INPUT: scriptExecution of type ScriptExecutionContext
  OUTPUT: boolean
  
  RETURN scriptExecution.hasStrictModeEnabled = true
         AND scriptExecution.commandFailed IN ['kubectl delete', 'kubectl get', 'cleanup operations']
         AND scriptExecution.currentSection = 'cleanup_conflicting_resources'
         AND scriptExecution.grafanaImportsSectionReached = false
END FUNCTION
```

### Examples

- **Example 1**: Script attempts `kubectl delete clusterrole monitoring-loki` but the resource doesn't exist. With `set -e`, script exits with code 1. Grafana imports never run. Terraform apply attempts to create existing Grafana team "webank-team" → 409 error "Team name taken"

- **Example 2**: Script attempts to delete a clusterrolebinding but lacks permissions. Script exits immediately. Existing datasource "Webank-Loki" is not imported. Terraform apply attempts to create it → 409 error "data source with the same name already exists"

- **Example 3**: kubectl command times out after 30s during cleanup. Script exits. Import report shows 0 Grafana resources imported. Terraform apply fails with multiple 409 conflicts for teams and datasources

- **Edge Case**: All cleanup commands succeed but Grafana API is temporarily unavailable. Script should continue, log the Grafana import failures, but still exit with code 0 to allow terraform apply to proceed (which will create the resources if they truly don't exist)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Successful import operations must continue to be reported in the JSON import report with correct counts
- Resources that don't exist must continue to be skipped with appropriate logging
- The import report structure and format must remain unchanged
- GCP-specific imports (service accounts, storage buckets) must continue to work correctly
- Kubernetes namespace and service account imports must continue to function as before
- The final JSON report must continue to include timestamps, imports array, skipped array, and errors array

**Scope:**
All inputs that do NOT involve command failures should be completely unaffected by this fix. This includes:
- Successful kubectl operations
- Successful terraform import operations
- Successful API calls to Grafana
- Report generation and formatting
- All existing success paths through the script

## Hypothesized Root Cause

Based on the bug description and code analysis, the root causes are:

1. **Overly Strict Error Handling**: The script uses `set -euo pipefail` which causes immediate exit on ANY command failure, including expected failures like attempting to delete non-existent resources
   - The cleanup section uses `--ignore-not-found` flag but this doesn't prevent all failure modes
   - Network timeouts, permission issues, or API unavailability still cause exits

2. **No Failure Isolation**: Individual command failures in the cleanup section prevent unrelated operations (Grafana imports) from executing
   - The cleanup and import sections are independent but treated as atomic
   - A failure in resource cleanup should not block resource imports

3. **Workflow Dependency on continue-on-error**: The workflow uses `continue-on-error: true` which masks the problem but doesn't solve it
   - The script exits with code 1, but the workflow continues anyway
   - This creates a false sense of success while leaving state incomplete

4. **Insufficient Error Context**: When the script exits early, there's no indication of which specific command failed or why
   - Debugging requires examining workflow logs to find the failure point
   - The import report is incomplete or not generated at all

## Correctness Properties

Property 1: Fault Condition - Script Continues on Command Failures

_For any_ script execution where a kubectl command, API call, or terraform import fails during cleanup or import operations, the fixed script SHALL log the error with context, continue executing subsequent operations, and exit with code 0 to allow the workflow to proceed.

**Validates: Requirements 2.1, 2.2, 2.6**

Property 2: Preservation - Successful Operations Unchanged

_For any_ script execution where all commands succeed, the fixed script SHALL produce exactly the same behavior as the original script, preserving all existing import functionality, report generation, and logging output.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `.github/scripts/import-existing-resources.sh`

**Function**: Script-wide error handling and cleanup_conflicting_resources function

**Specific Changes**:

1. **Remove Strict Mode**: Replace `set -euo pipefail` with `set -uo pipefail`
   - Keep `-u` (error on undefined variables) and `-o pipefail` (pipeline failure detection)
   - Remove `-e` (exit on error) to allow script to continue on failures
   - This is the primary change that enables resilience

2. **Add Failure Tracking**: Introduce a global failure counter and tracking mechanism
   - Add `FAILURE_COUNT=0` variable at script start
   - Add `FAILED_OPERATIONS=()` array to track which operations failed
   - Increment counter and append to array when operations fail

3. **Wrap Critical Operations**: Add explicit error handling around kubectl and API calls
   - Wrap cleanup operations with `|| { echo "Error: ..."; FAILURE_COUNT=$((FAILURE_COUNT+1)); }`
   - Ensure cleanup_conflicting_resources function continues on individual resource failures
   - Add error context to log messages (command, resource, error message)

4. **Enhance Logging**: Improve error messages to provide debugging context
   - Log the specific command that failed
   - Log the error output from failed commands
   - Add timestamps to error messages
   - Distinguish between expected failures (resource not found) and unexpected failures

5. **Update Exit Strategy**: Modify script exit to always return 0 but log failure summary
   - Keep `exit 0` at the end (already present)
   - Add failure summary before exit if FAILURE_COUNT > 0
   - Include failed operations list in the summary
   - Ensure import report is always generated even with failures

6. **Enhance cleanup_conflicting_resources**: Make the function more resilient
   - Add `|| true` to kubectl commands that may legitimately fail
   - Wrap deletion operations in error handling that logs but continues
   - Ensure the function never causes script exit

7. **Protect Grafana Import Section**: Ensure Grafana imports always execute
   - Add explicit check that this section runs regardless of prior failures
   - Wrap individual Grafana API calls with error handling
   - Log Grafana import failures but continue to next resource

### Implementation Strategy

The fix will be implemented in phases:

**Phase 1**: Remove strict mode and add failure tracking
- Change `set -euo pipefail` to `set -uo pipefail`
- Add FAILURE_COUNT and FAILED_OPERATIONS variables
- Test that script continues on failures

**Phase 2**: Add error handling to cleanup section
- Wrap kubectl delete commands with error handlers
- Update cleanup_conflicting_resources to never exit
- Test cleanup failures don't block imports

**Phase 3**: Add error handling to import sections
- Wrap import_resource calls with additional logging
- Ensure Grafana imports always execute
- Test that partial failures are properly reported

**Phase 4**: Enhance logging and reporting
- Add failure summary at script end
- Improve error messages with context
- Update import report to include failure details

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code by simulating various failure scenarios, then verify the fix works correctly and preserves existing behavior. Testing will involve both synthetic failures (simulated errors) and real-world scenarios (actual resource conflicts, permission issues).

### Exploratory Fault Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Create test scenarios that simulate kubectl command failures, API failures, and timeout conditions. Run these tests on the UNFIXED code to observe immediate script exit and incomplete import reports. Verify that Grafana imports are never reached when cleanup fails.

**Test Cases**:
1. **Cleanup Failure Test**: Simulate kubectl delete failure for non-existent clusterrole (will fail on unfixed code - script exits immediately)
2. **Permission Denied Test**: Simulate kubectl permission error during cleanup (will fail on unfixed code - script exits with error)
3. **Timeout Test**: Simulate kubectl timeout during resource deletion (will fail on unfixed code - script exits after timeout)
4. **Grafana API Unavailable Test**: Simulate Grafana API returning 503 during team lookup (will fail on unfixed code - script may exit depending on curl error handling)

**Expected Counterexamples**:
- Script exits with code 1 when any kubectl command fails
- Import report is incomplete or not generated when script exits early
- Grafana import section is never reached when cleanup section fails
- Possible causes: `set -e` causing immediate exit, no error isolation between sections, insufficient error handling in cleanup functions

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds (command failures occur), the fixed script produces the expected behavior (continues execution, logs errors, exits with code 0).

**Pseudocode:**
```
FOR ALL scriptExecution WHERE isBugCondition(scriptExecution) DO
  result := runImportScript_fixed(scriptExecution)
  ASSERT result.exitCode = 0
  ASSERT result.grafanaImportsSectionReached = true
  ASSERT result.importReportGenerated = true
  ASSERT result.errorLogged = true
  ASSERT result.failureSummaryPresent = true
END FOR
```

**Test Cases**:
1. **Cleanup Failure Resilience**: Inject kubectl delete failure, verify script continues to Grafana imports
2. **Multiple Failures Resilience**: Inject failures in cleanup AND Grafana API, verify script completes with full report
3. **Partial Success**: Inject failure in one cleanup operation, verify other cleanups and all imports succeed
4. **Complete Failure**: Inject failures in all operations, verify script still generates report and exits 0

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold (all commands succeed), the fixed script produces the same result as the original script.

**Pseudocode:**
```
FOR ALL scriptExecution WHERE NOT isBugCondition(scriptExecution) DO
  ASSERT runImportScript_original(scriptExecution) = runImportScript_fixed(scriptExecution)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for successful operations, then write property-based tests capturing that behavior. Compare outputs between original and fixed versions for success scenarios.

**Test Cases**:
1. **All Operations Succeed**: Run script with all resources existing and accessible, verify identical output between original and fixed versions
2. **Selective Imports**: Run script with some resources existing and some not, verify same import/skip decisions
3. **Report Format**: Verify JSON report structure and content are identical for success cases
4. **GCP Imports**: Verify GCP-specific imports (service accounts, buckets) produce identical results

### Unit Tests

- Test script with simulated kubectl failures in cleanup section
- Test script with simulated Grafana API failures
- Test script with mixed success/failure scenarios
- Test that failure counter increments correctly
- Test that failed operations are tracked in array
- Test that import report is always generated
- Test that exit code is always 0 after fix

### Property-Based Tests

- Generate random combinations of resource existence states and verify script handles all cases
- Generate random failure patterns (which commands fail) and verify script always completes
- Generate random API response scenarios and verify resilience
- Test that for any failure pattern, script produces valid JSON report
- Test that for any success pattern, output matches original script

### Integration Tests

- Test full workflow with actual GKE cluster and existing resources
- Test cleanup section with actual conflicting resources
- Test Grafana imports with actual Grafana instance
- Test that terraform apply succeeds after script runs with failures
- Test that 409 conflicts are eliminated after fix
- Test workflow end-to-end with continue-on-error removed (script should succeed on its own)

### Manual Testing Checklist

Before considering the fix complete, manually verify:
- [ ] Script continues when kubectl delete fails for non-existent resource
- [ ] Script continues when kubectl times out
- [ ] Script continues when Grafana API returns errors
- [ ] Grafana imports always execute regardless of cleanup failures
- [ ] Import report is always generated with correct structure
- [ ] Failure summary is logged when failures occur
- [ ] Exit code is always 0
- [ ] Terraform apply succeeds after script runs
- [ ] No 409 conflicts occur for existing Grafana resources
- [ ] Workflow can remove continue-on-error flag and still succeed
