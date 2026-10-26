*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
# Any resolvable-looking name: the schema demands a dot, nothing resolves it.
${TEST_HOST}    privatebin.ns8-ci.test
${BASE_CONFIG}    "host":"${TEST_HOST}","lets_encrypt":false,"name":"CI \\"Paste\\" $HOME","notice":"Test banner","info":"","expire_default":"1day","expire_max":"1month","discussion":true,"open_discussion":false,"burn_after_reading_selected":false,"qrcode":true,"file_upload":true,"size_limit":20,"language_selection":true,"language_default":"auto","private_creators":false
# 1x1 PNG
${LOGO}    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==

*** Keywords ***
Get page
    [Arguments]    ${path}
    ${page} =    Execute Command
    ...    curl -sk --resolve ${TEST_HOST}:443:127.0.0.1 https://${TEST_HOST}${path}
    RETURN    ${page}

PrivateBin answers
    ${page} =    Get page    /
    Should Contain    ${page}    <title>CI "Paste" $HOME</title>

*** Test Cases ***
Check if privatebin is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check the fresh configuration
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config}[host]    ${EMPTY}
    Should Be Equal    ${config}[expire_default]    1week
    Should Not Be True    ${config}[file_upload]
    Should Not Be True    ${config}[logo_set]

Check a default expiration above the maximum is rejected
    ${output} =    Run task    module/${module_id}/configure-module
    ...    {${BASE_CONFIG.replace('"expire_default":"1day"', '"expire_default":"1year"')}}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    expire_default_above_max

Check an SVG logo is rejected
    ${output} =    Run task    module/${module_id}/configure-module
    ...    {${BASE_CONFIG},"logo":"PHN2Zz48L3N2Zz4="}
    ...    decode_json=${FALSE}    rc_expected=2
    Should Contain    ${output}    logo_invalid_format

Check if privatebin can be configured
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},"logo":"${LOGO}"}

Check if privatebin configuration reads back
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config}[host]    ${TEST_HOST}
    Should Be Equal    ${config}[name]    CI "Paste" $HOME
    Should Be Equal As Integers    ${config}[size_limit]    20
    Should Be True    ${config}[logo_set]

Check if privatebin answers with the settings
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    PrivateBin answers
    ${page} =    Get page    /
    Should Contain    ${page}    Test banner
    Should Contain    ${page}    value="1month"
    Should Not Contain    ${page}    value="1year"

Check if the custom logo is served
    ${svg} =    Get page    /img/icon.svg
    Should Contain    ${svg}    data:image/png;base64,${LOGO}

Check if the original logo comes back
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},"logo":""}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Not Be True    ${config}[logo_set]
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    PrivateBin answers
    ${svg} =    Get page    /img/icon.svg
    Should Not Contain    ${svg}    data:image/png

Check if the purge timer is active
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active privatebin-purge.timer
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user start privatebin-purge.service
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0

Check if privatebin is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
