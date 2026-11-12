*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
# Any resolvable-looking name: the schema demands a dot, nothing resolves it.
${TEST_HOST}    privatebin.ns8-ci.test
${BASE_CONFIG}    "host":"${TEST_HOST}","lets_encrypt":false,"name":"CI \\"Paste\\" $HOME","notice":"Test banner","info":"","expire_default":"1day","expire_max":"1month","discussion":true,"open_discussion":false,"burn_after_reading_selected":false,"qrcode":true,"file_upload":true,"size_limit":20,"language_selection":true,"language_default":"auto","private_creators":false,"rate_limit":45,"ldap_domain":""
${USER_DOMAIN}    privatebin.ns8-ci.test
${COOKIES}    /tmp/privatebin.cookies
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

Curl status
    [Documentation]    Query PrivateBin through Traefik with the cookie jar,
    ...                return the status code and the redirect target.
    [Arguments]    ${path}    ${options}=${EMPTY}
    ${status} =    Execute Command
    ...    curl -sk -o /dev/null -w '\%{http_code} \%{redirect_url}' --resolve ${TEST_HOST}:443:127.0.0.1 -b ${COOKIES} -c ${COOKIES} ${options} https://${TEST_HOST}${path}
    RETURN    ${status}

Log in to PrivateBin
    [Arguments]    ${user}    ${password}
    ${status} =    Curl status    /_auth/api/login
    ...    -X POST -H 'Content-Type: application/json' --data '{"username":"${user}","password":"${password}"}'
    RETURN    ${status.strip()}

Editor asks for a login
    ${status} =    Curl status    /
    Should Be Equal    ${status}    302 https://${TEST_HOST}/_auth/login

Editor is open
    ${status} =    Curl status    /
    Should Be Equal    ${status.strip()}    200

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

Check if the user domain is installed
    ${response} =    Run task    add-internal-provider    {"image":"openldap","node":1}
    Set Suite Variable    ${ldap_id}    ${response['module_id']}
    Run task    module/${ldap_id}/configure-module
    ...    {"domain":"${USER_DOMAIN}","admuser":"admin","admpass":"Nethesis,1234","provision":"new-domain"}
    Run task    module/${ldap_id}/add-user
    ...    {"user":"alice","display_name":"Alice","password":"Nethesis,1234"}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Contain    ${config}[ldap_domain_list]    ${USER_DOMAIN}

Check if creation asks for a login
    Execute Command    rm -f ${COOKIES}
    ${ldap_config} =    Evaluate    $BASE_CONFIG.replace('"ldap_domain":""', '"ldap_domain":"%s"' % $USER_DOMAIN)
    Run task    module/${module_id}/configure-module    {${ldap_config}}
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    Editor asks for a login
    ${login_page} =    Curl status    /_auth/login
    Should Be Equal    ${login_page.strip()}    200
    ${post} =    Curl status    /    -H 'X-Requested-With: JSONHttpRequest' --data '{"v":2,"ct":"x"}'
    Should Be Equal    ${post.strip()}    401

Check if a document link opens without login
    ${status} =    Curl status    /?0123456789abcdef
    Should Be Equal    ${status.strip()}    200
    ${status} =    Curl status    /js/privatebin.js
    Should Be Equal    ${status.strip()}    200

Check if a wrong password is refused
    ${status} =    Log in to PrivateBin    alice    wrong-password
    Should Be Equal    ${status}    401
    ${output} =    Execute Command    journalctl --since -5min --no-pager | grep -c "login failed user='alice'"
    Should Be True    ${output} >= 1

Check if a logged in user can create documents
    ${status} =    Log in to PrivateBin    alice    Nethesis,1234
    Should Be Equal    ${status}    200
    Editor is open
    ${answer} =    Execute Command
    ...    curl -sk --resolve ${TEST_HOST}:443:127.0.0.1 -b ${COOKIES} -H 'X-Requested-With: JSONHttpRequest' --data '{"v":2,"ct":"x"}' https://${TEST_HOST}/
    Should Contain    ${answer}    Invalid data

Check if logging out closes the editor
    Curl status    /_auth/api/logout    -X POST
    Editor asks for a login

Check if repeated failures are blocked
    FOR    ${i}    IN RANGE    10
        Log in to PrivateBin    alice    wrong-password
    END
    ${status} =    Log in to PrivateBin    alice    Nethesis,1234
    Should Be Equal    ${status}    429

Check if creation is open again without a domain
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG}}
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    Editor is open
    Execute Command    rm -f ${COOKIES}

Check if an update keeps the configuration
    Run task    module/${module_id}/configure-module    {${BASE_CONFIG}}
    Run task    update-module    {"module_url":"${IMAGE_URL}","instances":["${module_id}"],"force":true}
    ${config} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${config}[name]    CI "Paste" $HOME
    Should Be Equal As Integers    ${config}[rate_limit]    45
    Wait Until Keyword Succeeds    20 times    3 seconds
    ...    PrivateBin answers

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

Check if the user domain is removed correctly
    Run task    remove-internal-domain    {"domain":"${USER_DOMAIN}"}
