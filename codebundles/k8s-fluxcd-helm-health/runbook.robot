*** Settings ***
Documentation       This codebundle runs a series of tasks to identify potential helm release issues related to Flux managed Helm objects. 
Metadata            Author    stewartshea
Metadata            Display Name    Kubernetes FluxCD HelmRelease TaskSet
Metadata            Supports    Kubernetes,AKS,EKS,GKE,OpenShift,FluxCD
Library             RW.Core
Library             RW.CLI
Library             RW.platform

Suite Setup         Suite Initialization


*** Tasks ***
List all available FluxCD Helmreleases    
    [Documentation]    List all FluxCD helmreleases that are visible to the kubeconfig.    
    [Tags]        FluxCD     Helmrelease     Available    List
    ${helmreleases}=    RW.CLI.Run Cli
    ...    cmd=${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} -n ${NAMESPACE} --context ${CONTEXT}
    ...    target_service=${kubectl}
    ...    env=${env}
    ...    secret_file__kubeconfig=${KUBECONFIG}
    ...    render_in_commandlist=true
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Helmreleases available: \n ${helmreleases.stdout}
    RW.Core.Add Pre To Report    Commands Used:\n${history}

Fetch Installed FluxCD Helmrelease Versions  
    [Documentation]    List helmreleases and  the last attempted software version and the current running version.  
    [Tags]        FluxCD     Helmrelease    Versions
    ${helmrelease_versions}=    RW.CLI.Run Cli
    ...    cmd=${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} -n ${NAMESPACE} -o=jsonpath="{range .items[*]}{'\\nName: '}{@.metadata.name}{'\\nlastAppliedRevision:'}{@.status.lastAppliedRevision}{'\\nlastAttemptedRevision:'}{@.status.lastAttemptedRevision}{'\\n---'}{end}" --context ${CONTEXT} || true
    ...    target_service=${kubectl}
    ...    env=${env}
    ...    secret_file__kubeconfig=${KUBECONFIG}
    ...    render_in_commandlist=true
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Helmreleases status errors: \n ${helmrelease_versions.stdout}
    RW.Core.Add Pre To Report    Commands Used:\n${history}

Fetch Mismatched FluxCD HelmRelease Version
    [Documentation]    List helmreleases and use jq to display any releases where the last attempted software revision doesn't match the current running revision. Requires jq.  
    [Tags]        FluxCD     Helmrelease    Version    Mismatched    Unhealthy
    ${helmrelease_version_mismatches}=    RW.CLI.Run Cli
    ...    cmd=${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} -n ${NAMESPACE} -o json --context ${CONTEXT} | jq -r '.items[] | select(.status.lastAppliedRevision!=.status.lastAttemptedRevision) | "Name: " + .metadata.name + " Last Attempted Version: " + .status.lastAttemptedRevision + " Last Applied Revision: " + .status.lastAppliedRevision'
    ...    target_service=${kubectl}
    ...    env=${env}
    ...    secret_file__kubeconfig=${KUBECONFIG}
    ...    render_in_commandlist=true
    ${regexp}=    Catenate
    ...    (?m)(?P<line>.+)
    RW.CLI.Parse Cli Output By Line
    ...    rsp=${helmrelease_version_mismatches}
    ...    lines_like_regexp=${regexp}
    ...    set_severity_level=2
    ...    set_issue_expected=Flux HelmRelease lastApplied and lastAttempted Revision should match
    ...    set_issue_actual=Flux HelmRelease lastApplied and lastAttempted Revision do not match
    ...    set_issue_title=FluxCD Helmrelease Version Mismatch
    ...    set_issue_details=The currently applied helm release does not match the attemped installation version (found $line). Check fluxcd helm release version configuration, fluxcd helm release events, or namespace events. 
    ...    line__raise_issue_if_contains=Name
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Helmreleases version mismatches: \n ${helmrelease_version_mismatches.stdout}
    RW.Core.Add Pre To Report    Commands Used:\n${history}

Fetch FluxCD HelmRelease Error Messages    
    [Documentation]    List helmreleases and display the status conditions message for any helmreleases that are not in a Ready state. 
    [Tags]        FluxCD     Helmrelease    Errors     Unhealthy    Message
    ${helmrelease_errors}=    RW.CLI.Run Cli
    ...    cmd=${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} -n ${NAMESPACE} -o=jsonpath="{range .items[?(@.status.conditions[].status=='False')]}{'-----\\nName: '}{@.metadata.name}{'\\n'}{@.status.conditions[*].message}{'\\n'}{end}" --context ${CONTEXT} || true
    ...    target_service=${kubectl}
    ...    env=${env}
    ...    secret_file__kubeconfig=${KUBECONFIG}
    ...    render_in_commandlist=true
   ${regexp}=    Catenate
    ...    (?m)(?P<line>.+)
    RW.CLI.Parse Cli Output By Line
    ...    rsp=${helmrelease_errors}
    ...    lines_like_regexp=${regexp}
    ...    set_severity_level=2
    ...    set_issue_expected=Flux HelmRelease Objects should be in a ready state 
    ...    set_issue_actual=Flux HelmRelease Objects are not in a ready state
    ...    set_issue_title=FluxCD Helmrelease Errors
    ...    set_issue_details=FluxCD helm releases are found to be in an errored state (current state: $line). Check the fluxcd helmrelease status condition messages, helmrelease configuration, fluxcd helm controller, or kustomization objects. Check fluxcd namespace events or helm release namespace events. 
    ...    line__raise_issue_if_contains=Name
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    Helmreleases status errors: \n ${helmrelease_errors.stdout}
    RW.Core.Add Pre To Report    Commands Used:\n${history}

Check for Available Helm Chart Updates    
    [Documentation]    List all helmreleases in namespace and check for available helmchart updates. 
    [Tags]        FluxCD     Helmchart    Errors     Unhealthy    Message   HelmRelease
    ${helmchart_updates_available}=    RW.CLI.Run Cli
    ...    cmd=namespace="${NAMESPACE}" context="${CONTEXT}"; helm_releases=$(${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} -n "$namespace" --context "$context" -o json | jq -r '.items[] | .metadata.name'); echo "$helm_releases" | while IFS= read -r release; do chart_details=$(${KUBERNETES_DISTRIBUTION_BINARY} get ${RESOURCE_NAME} "$release" -n "$namespace" --context "$context" -o json | jq -r '.spec.chart.spec // empty'); if [[ -n "$chart_details" ]]; then chart_kind=$(echo "$chart_details" | jq -r '.sourceRef.kind // empty'); chart_name=$(echo "$chart_details" | jq -r '.chart // empty'); chart_source_name=$(echo "$chart_details" | jq -r '.sourceRef.name // empty'); chart_namespace=$(echo "$chart_details" | jq -r '.sourceRef.namespace // empty'); chart_version=$(echo "$chart_details" | jq -r '.version // "N/A"'); if [[ "$chart_kind" == "HelmRepository" && -n "$chart_name" && -n "$chart_namespace" ]]; then repo_url=$(${KUBERNETES_DISTRIBUTION_BINARY} get helmrepositories.source.toolkit.fluxcd.io "$chart_source_name" -n "$chart_namespace" --context "$context" -o json | jq -r '.spec.url // empty'); if [[ -n "$repo_url" ]]; then temp_repo_name="$chart_source_name-temp-$release"; add_repo=$(helm repo add "$temp_repo_name" "$repo_url"); available_chart_version=$(helm search repo "$temp_repo_name"/"$chart_name" --version ">$chart_version" --output json | jq -r '.[].version'); if [[ -n "$available_chart_version" ]]; then sorted_versions=($(echo "\${available_chart_version[@]}" | tr ' ' '\\n' | sort -V)); available_version=\${sorted_versions[-1]}; version_update_available="True"; else available_version="N/A"; version_update_available="False"; fi; remove_repo=$(helm repo remove "$temp_repo_name"); else available_version="N/A"; version_update_available="False"; fi; else available_version="N/A"; version_update_available="False"; fi; else chart_name="N/A"; chart_namespace="N/A"; chart_version="N/A"; available_version="N/A"; version_update_available="False"; fi; echo "Release: $release | Chart: $chart_namespace/$chart_name | Installed Version: $chart_version | Available Update: $version_update_available | Available Version: $available_version"; done
    ...    target_service=${kubectl}
    ...    env=${env}
    ...    secret_file__kubeconfig=${KUBECONFIG}
    ...    render_in_commandlist=true
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report    HelmChart Version Update Details: \n ${helmchart_updates_available.stdout}
    RW.Core.Add Pre To Report    Commands Used:\n${history}

*** Keywords ***
Suite Initialization
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration used to connect to cluster(s).
    ...    pattern=\w*
    ...    example=For examples, start here https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
    ${kubectl}=    RW.Core.Import Service    kubectl
    ...    description=The location service used to interpret shell commands.
    ...    default=kubectl-service.shared
    ...    example=kubectl-service.shared
    ${DISTRIBUTION}=    RW.Core.Import User Variable    DISTRIBUTION
    ...    type=string
    ...    description=Which distribution of Kubernetes to use for operations, such as: Kubernetes, OpenShift, etc.
    ...    pattern=\w*
    ...    enum=[Kubernetes,GKE,OpenShift]
    ...    example=Kubernetes
    ...    default=Kubernetes
    ${KUBERNETES_DISTRIBUTION_BINARY}=    RW.Core.Import User Variable    KUBERNETES_DISTRIBUTION_BINARY
    ...    type=string
    ...    description=Which binary to use for Kubernetes CLI commands.
    ...    enum=[kubectl,oc]
    ...    example=kubectl
    ...    default=kubectl
    ${NAMESPACE}=    RW.Core.Import User Variable    NAMESPACE
    ...    type=string
    ...    description=The name of the Kubernetes namespace to scope actions and searching to. Accepts a single namespace in the format `-n namespace-name` or `--all-namespaces`. 
    ...    pattern=\w*
    ...    example=-n my-namespace
    ...    default=--all-namespaces
    ${RESOURCE_NAME}=    RW.Core.Import User Variable    RESOURCE_NAME
    ...    type=string
    ...    description=The short or long name of the Kubernetes helmrelease resource to search for. These might vary by helm controller implementation, and are best to use full crd name. 
    ...    pattern=\w*
    ...    example=helmreleases.helm.toolkit.fluxcd.io
    ...    default=helmreleases
    ${CONTEXT}=    RW.Core.Import User Variable    CONTEXT
    ...    type=string
    ...    description=Which Kubernetes context to operate within.
    ...    pattern=\w*
    ...    default=default
    ...    example=my-main-cluster
    Set Suite Variable    ${KUBERNETES_DISTRIBUTION_BINARY}    ${KUBERNETES_DISTRIBUTION_BINARY}
    Set Suite Variable    ${kubeconfig}    ${kubeconfig}
    Set Suite Variable    ${RESOURCE_NAME}    ${RESOURCE_NAME}
    Set Suite Variable    ${NAMESPACE}    ${NAMESPACE}
    Set Suite Variable    ${env}    {"KUBECONFIG":"./${kubeconfig.key}"}
