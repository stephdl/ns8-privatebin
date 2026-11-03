*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
# install tests the image under test, update starts from the stephdl forge release
${SCENARIO}    install
# Any resolvable-looking name: the schema demands a dot, nothing resolves it.
${TEST_HOST}    privatebin.ns8-ci.test
${BASE_CONFIG}    "host":"${TEST_HOST}","lets_encrypt":false,"name":"CI \\"Paste\\" $HOME","notice":"Test banner","info":"","expire_default":"1day","expire_max":"1month","discussion":true,"open_discussion":false,"burn_after_reading_selected":false,"qrcode":true,"file_upload":true,"size_limit":20,"language_selection":true,"language_default":"auto","private_creators":false,"rate_limit":45
# Random bytes: PrivateBin refuses a low entropy ciphertext, it never decrypts it
${CIPHERTEXT}    Q2WeGrkRJu9IIss/xjqKWBo5RXcHxf2LS1yxUGvYkChAtiW5Q7En8eh+h5jGqC0MRa5cxilIpmKREz9VR1Oomc+cFE22vsG1oCNhze8+wWLBPLKVxrqIRCXaAe8c7AmpdpigESc3UJCQIgxa8FcCC7Tw4kAyclHS7RechkA/ThutETeoWauCfjTaRhXSwv7xv58yKupXD6zQfK46fXMYwW5dQ74Absoqwm/uFzAU94U6RzFIPyioSlC65sfD1OcPJrA4q6OejYR3Z/q+v7wUnBQALaoKRQWs9mI30mJ5o3sCNox9jpM9/MkmYNrcpedA
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

Post a document from
    [Arguments]    ${forwarded_for}
    # Straight to the app port: Traefik would replace X-Forwarded-For with the
    # test runner address. The body is not a valid document, PrivateBin answers
    # "Invalid data" once the address checks pass.
    ${port} =    Execute Command    runagent -m ${module_id} sh -c 'grep ^TCP_PORT= environment | cut -d= -f2'
    ${answer} =    Execute Command
    ...    curl -s -H 'X-Requested-With: JSONHttpRequest' -H 'X-Forwarded-For: ${forwarded_for}' --data '{"v":2,"ct":"x"}' http://127.0.0.1:${port}/
    RETURN    ${answer}

Enable the stephdl forge
    ${repos} =    Execute Command    api-cli run cluster/list-repositories
    IF    '"name": "stephdl"' in $repos    RETURN
    ${rc} =    Execute Command
    ...    api-cli run add-repository --data '{"name":"stephdl","url":"https://forge.de-labrusse.fr/ns8/updates/","status":true}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Read the stored document
    ${port} =    Execute Command    runagent -m ${module_id} sh -c 'grep ^TCP_PORT= environment | cut -d= -f2'
    ${answer} =    Execute Command
    ...    curl -s -H 'X-Requested-With: JSONHttpRequest' 'http://127.0.0.1:${port}/?${document_id}'
    # PrivateBin escapes the slashes in its JSON answer
    ${document} =    Evaluate    json.loads($answer)    modules=json
    Should Be Equal    ${document}[ct]    ${CIPHERTEXT}

*** Test Cases ***
Check if privatebin is installed correctly
    IF    '${SCENARIO}' == 'update'
        Enable the stephdl forge
        ${image} =    Set Variable    privatebin
    ELSE
        ${image} =    Set Variable    ${IMAGE_URL}
    END
    ${output}  ${rc} =    Execute Command    add-module ${image} 1
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

Check if the delay between documents is applied
    ${conf} =    Execute Command    runagent -m ${module_id} grep -E "^(limit|creators)" privatebin/conf.php
    Should Contain    ${conf}    limit = 45
    Should Not Contain    ${conf}    creators
    ${first} =    Post a document from    203.0.113.7
    Should Contain    ${first}    Invalid data
    ${second} =    Post a document from    203.0.113.7
    Should Contain    ${second}    Please wait 45 seconds
    # The delay counts per address
    ${other} =    Post a document from    203.0.113.8
    Should Contain    ${other}    Invalid data

Check if a document is stored
    # A well formed body from an address with no delay yet
    ${port} =    Execute Command    runagent -m ${module_id} sh -c 'grep ^TCP_PORT= environment | cut -d= -f2'
    ${body} =    Set Variable    {"v":2,"adata":[["AAAAAAAAAAAAAAAAAAAAAA==","AAAAAAAAAAA=",100000,256,128,"aes","gcm","zlib"],"plaintext",0,0],"ct":"${CIPHERTEXT}","meta":{"expire":"1week"}}
    ${answer} =    Execute Command
    ...    curl -s -H 'X-Requested-With: JSONHttpRequest' -H 'X-Forwarded-For: 203.0.113.50' --data '${body}' http://127.0.0.1:${port}/
    ${result} =    Evaluate    json.loads($answer)    modules=json
    Should Be Equal As Integers    ${result}[status]    0
    Set Global Variable    ${document_id}    ${result}[id]
    Read the stored document

Check if the size limits follow the setting
    ${nginx} =    Execute Command    runagent -m ${module_id} cat privatebin/nginx.conf
    Should Contain    ${nginx}    client_max_body_size 22M;
    ${php} =    Execute Command    runagent -m ${module_id} cat privatebin/php.ini
    Should Contain    ${php}    post_max_size=22M
    Should Contain    ${php}    upload_max_filesize=22M

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

Check if only private networks can create documents
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG.replace('"private_creators":false', '"private_creators":true')}}
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    PrivateBin answers
    ${lan} =    Post a document from    192.168.1.5
    Should Contain    ${lan}    Invalid data
    # No delay for the creators networks
    ${again} =    Post a document from    192.168.1.5
    Should Contain    ${again}    Invalid data
    ${internet} =    Post a document from    8.8.8.8
    Should Contain    ${internet}    not authorized
    # Behind a trusted proxy the list is read from the right: the first public address is the visitor
    ${proxied_lan} =    Post a document from    192.168.1.5, 10.0.0.1
    Should Contain    ${proxied_lan}    Invalid data
    ${proxied_internet} =    Post a document from    192.168.1.5, 8.8.8.8, 10.0.0.1
    Should Contain    ${proxied_internet}    not authorized

Check if an update keeps the configuration and the documents
    # In the update scenario the module comes from the forge release, otherwise
    # it updates to the same image: both run the update-module.d hooks
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG},"logo":"${LOGO}"}
    Run task    update-module    {"module_url":"${IMAGE_URL}","instances":["${module_id}"],"force":true}
    ${image} =    Execute Command    runagent -m ${module_id} sh -c 'grep ^IMAGE_URL= environment | cut -d= -f2'
    Should Be Equal    ${image}    ${IMAGE_URL}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config}[name]    CI "Paste" $HOME
    Should Be Equal As Integers    ${config}[rate_limit]    45
    Should Be True    ${config}[logo_set]
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    PrivateBin answers
    ${svg} =    Get page    /img/icon.svg
    Should Contain    ${svg}    data:image/png;base64,${LOGO}
    Read the stored document

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
