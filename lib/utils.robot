*** Settings ***
Resource                ../lib/resource.txt
Resource                ../lib/rest_client.robot
Resource                ../lib/connection_client.robot
Library                 DateTime
Library                 Process
Library                 OperatingSystem

*** Variables ***
${SYSTEM_SHUTDOWN_TIME}       ${5}
${dbuscmdBase} =    dbus-send --system --print-reply --dest=org.openbmc.settings.Host
${dbuscmdGet} =   /org/openbmc/settings/host0  org.freedesktop.DBus.Properties.Get
${dbuscmdString} =   string:"org.openbmc.settings.Host" string:

*** Keywords ***
Wait For Host To Ping
    [Arguments]  ${host}  ${timeout}=${OPENBMC_REBOOT_TIMEOUT}min
    ...          ${interval}=5 sec

    # host      The DNS name or IP of the host to ping.
    # timeout   The amount of time after which attempts to ping cease.
    # interval  The amount of time in between attempts to ping.

    Wait Until Keyword Succeeds  ${timeout}  ${interval}  Ping Host  ${host}

Ping Host
    [Arguments]     ${host}
    Should Not Be Empty    ${host}   msg=No host provided
    ${RC}   ${output} =     Run and return RC and Output    ping -c 4 ${host}
    Log     RC: ${RC}\nOutput:\n${output}
    Should be equal     ${RC}   ${0}

Get Boot Progress
    ${state} =     Read Attribute    /org/openbmc/sensors/host/BootProgress    value
    [return]  ${state}

Is Power On
    ${state}=  Get Power State
    Should be equal  ${state}  ${1}

Is Power Off
    ${state}=  Get Power State
    Should be equal  ${state}  ${0}

Initiate Power On
    [Documentation]  Initiates the power on and waits until the Is Power On
    ...  keyword returns that the power state has switched to on.
    @{arglist}=   Create List
    ${args}=     Create Dictionary    data=@{arglist}
    ${resp}=   Call Method    /org/openbmc/control/chassis0/    powerOn    data=${args}
    should be equal as strings      ${resp.status_code}     ${HTTP_OK}
    Wait Until Keyword Succeeds	  3 min    	10 sec    Is Power On

Initiate Power Off
    [Documentation]  Initiates the power off and waits until the Is Power Off
    ...  keyword returns that the power state has switched to off.
    @{arglist}=   Create List
    ${args}=     Create Dictionary    data=@{arglist}
    ${resp}=   Call Method    /org/openbmc/control/chassis0/    powerOff   data=${args}
    should be equal as strings      ${resp.status_code}     ${HTTP_OK}
    Wait Until Keyword Succeeds	  1 min    	10 sec    Is Power Off

Trigger Warm Reset
    log to console    "Triggering warm reset"
    ${data} =   create dictionary   data=@{EMPTY}
    ${resp} =   openbmc post request    /org/openbmc/control/bmc0/action/warmReset     data=${data}
    Should Be Equal As Strings      ${resp.status_code}     ${HTTP_OK}
    ${session_active}=   Check If warmReset is Initiated
    Run Keyword If   '${session_active}' == '${True}'
    ...    Fail   msg=warm reset didn't occur

    Sleep   ${SYSTEM_SHUTDOWN_TIME}min
    Wait For Host To Ping   ${OPENBMC_HOST}

Check OS
    [Documentation]  Attempts to ping the host OS and then checks that the host
    ...              OS is up by running an SSH command.

    [Arguments]  ${os_host}=${OS_HOST}  ${os_username}=${OS_USERNAME}
    ...          ${os_password}=${OS_PASSWORD}
    [Teardown]  Close Connection

    # os_host           The DNS name/IP of the OS host associated with our BMC.
    # os_username       The username to be used to sign on to the OS host.
    # os_password       The password to be used to sign on to the OS host.

    # Attempt to ping the OS. Store the return code to check later.
    ${ping_rc}=  Run Keyword and Return Status  Ping Host  ${os_host}

    Open connection  ${os_host}
    Login  ${os_username}  ${os_password}

    ${output}  ${stderr}  ${rc}=  Execute Command  uptime  return_stderr=True
    ...        return_rc=True

    # If the return code returned by "Execute Command" is non-zero, this keyword
    # will fail.
    Should Be Equal  ${rc}      ${0}
    # We will likewise fail if there is any stderr data.
    Should Be Empty  ${stderr}

    # We will likewise fail if the OS did not ping, as we could SSH but not ping
    Should Be Equal As Strings  ${ping_rc}  ${TRUE}

Wait for OS
    [Documentation]  Waits for the host OS to come up via calls to "Check OS".
    [Arguments]  ${os_host}=${OS_HOST}  ${os_username}=${OS_USERNAME}
    ...          ${os_password}=${OS_PASSWORD}  ${timeout}=${OS_WAIT_TIMEOUT}

    # os_host           The DNS name or IP of the OS host associated with our
    #                   BMC.
    # os_username       The username to be used to sign on to the OS host.
    # os_password       The password to be used to sign on to the OS host.
    # timeout           The timeout in seconds indicating how long you're
    #                   willing to wait for the OS to respond.

    # The interval to be used between calls to "Check OS".
    ${interval}=  Set Variable  5

    Wait Until Keyword Succeeds  ${timeout} sec  ${interval}  Check OS
    ...                          ${os_host}  ${os_username}  ${os_password}

Get BMC State
    [Documentation]  Returns the state of the BMC as a string. (i.e: BMC_READY)
    @{arglist}=  Create List
    ${args}=  Create Dictionary  data=@{arglist}
    ${resp}=  Call Method  /org/openbmc/managers/System/  getSystemState
    ...        data=${args}
    Should be equal as strings  ${resp.status_code}  ${HTTP_OK}
    ${content}=  to json  ${resp.content}
    [return]  ${content["data"]}

Get Power State
    [Documentation]  Returns the power state as an integer. Either 0 or 1.
    @{arglist}=  Create List
    ${args}=  Create Dictionary  data=@{arglist}
    ${resp}=  Call Method  /org/openbmc/control/chassis0/  getPowerState
    ...        data=${args}
    Should be equal as strings  ${resp.status_code}  ${HTTP_OK}
    ${content}=  to json  ${resp.content}
    [return]  ${content["data"]}

Clear BMC Record Log
    [Documentation]  Clears all the event logs on the BMC. This would be
    ...              equivalent to ipmitool sel clear.
    @{arglist}=   Create List
    ${args}=     Create Dictionary    data=@{arglist}
    ${resp}=   Call Method    /org/openbmc/records/events/    clear  data=${args}
    should be equal as strings      ${resp.status_code}     ${HTTP_OK}

Copy PNOR to BMC
    Import Library      SCPLibrary      WITH NAME       scp
    Open Connection for SCP
    Log    Copying ${PNOR_IMAGE_PATH} to /tmp
    scp.Put File    ${PNOR_IMAGE_PATH}   /tmp

Flash PNOR
    [Documentation]    Calls flash bios update method to flash PNOR image
    [arguments]    ${pnor_image}
    @{arglist}=   Create List    ${pnor_image}
    ${args}=     Create Dictionary    data=@{arglist}
    ${resp}=   Call Method    /org/openbmc/control/flash/bios/    update  data=${args}
    should be equal as strings      ${resp.status_code}     ${HTTP_OK}
    Wait Until Keyword Succeeds    2 min   10 sec    Is PNOR Flashing

Get Flash BIOS Status
    [Documentation]  Returns the status of the flash BIOS API as a string. For
    ...              example 'Flashing', 'Flash Done', etc
    ${data}=      Read Properties     /org/openbmc/control/flash/bios
    [return]    ${data['status']}

Is PNOR Flashing
    [Documentation]  Get BIOS 'Flashing' status. This indicates that PNOR
    ...              flashing has started.
    ${status}=    Get Flash BIOS Status
    should be equal as strings     ${status}     Flashing

Is PNOR Flash Done
    [Documentation]  Get BIOS 'Flash Done' status.  This indicates that the
    ...              PNOR flashing has completed.
    ${status}=    Get Flash BIOS Status
    should be equal as strings     ${status}     Flash Done

Is System State Host Booted
    [Documentation]  Checks whether system state is HOST_BOOTED.
    ${state}=    Get BMC State
    should be equal as strings     ${state}     HOST_BOOTED

Verify Ping and REST Authentication
    ${l_ping} =   Run Keyword And Return Status
    ...    Ping Host  ${OPENBMC_HOST}
    Run Keyword If  '${l_ping}' == '${False}'
    ...    Fail   msg=Ping Failed

    ${l_rest} =   Run Keyword And Return Status
    ...    Initialize OpenBMC
    Run Keyword If  '${l_rest}' == '${False}'
    ...    Fail   msg=REST Authentication Failed

    # Just to make sure the SSH is working for SCP
    Open Connection And Log In
    ${system}   ${stderr}=    Execute Command   hostname   return_stderr=True
    Should Be Empty     ${stderr}


Check If BMC is Up
    [Documentation]  Wait for Host to be online. Checks every X seconds
    ...              interval for Y minutes and fails if timed out.
    ...              Default MAX timedout is 10 min, interval 10 seconds.
    [arguments]      ${max_timeout}=${OPENBMC_REBOOT_TIMEOUT}
    ...              ${interval}=10 sec

    Wait Until Keyword Succeeds
    ...   ${max_timeout}  ${interval}   Verify Ping and REST Authentication


Check If warmReset is Initiated
    [Documentation]  Ping would be still alive, so try SSH to connect
    ...              if fails the ports are down indicating reboot
    ...              is in progress
    ${alive}=   Run Keyword and Return Status
    ...    Open Connection And Log In
    Return From Keyword If   '${alive}' == '${False}'    ${False}
    [return]    ${True}

Flush REST Sessions
    [Documentation]   Removes all the active session objects
    Delete All Sessions

Initialize DBUS cmd
    [Documentation]  Initialize dbus string with property string to extract
    [arguments]   ${boot_property}
    ${cmd} =     Catenate  ${dbuscmdBase} ${dbuscmdGet} ${dbuscmdString}
    ${cmd} =     Catenate  ${cmd}${boot_property}
    Set Global Variable   ${dbuscmd}     ${cmd}


Start SOL Console Logging
    [Documentation]   Start logging to a file in /tmp so that it can
    ...               be read by any other test cases. Stop existing
    ...               running client processes if there is any.
    ...               By default logging at /tmp/obmc-console.log else
    ...               user input location.
    ...               The File is appended with datetime and pid of
    ...               process which created this log file.
    [Arguments]       ${file_path}=/tmp/obmc-console.log

    Open Connection And Log In

    ${cur_time}=    Get Time Stamp
    Set Global Variable   ${LOG_TIME}   ${cur_time}
    Start Command
    ...  obmc-console-client > ${file_path}-${LOG_TIME}_$$


Stop SOL Console Logging
    [Documentation]   Login to BMC and Stop the obmc-console-client process.
    ...               Find the pids from the log to filter the one started by
    ...               specific test datetime and stop that process only.
    ...               Ignore if there is no process running and return message
    ...               "No obmc-console-client process running"
    ...               By default retrieving log from /tmp/obmc-console.log else
    ...               user input location.
    [Arguments]       ${file_path}=/tmp/obmc-console.log

    Open Connection And Log In

    ${pid}  ${stderr} =
    ...  Execute Command
    ...  ls ${file_path}-${LOG_TIME}_* | cut -d'_' -f 2
    ...  return_stderr=True
    Should Be Empty     ${stderr}

    ${rc}=
    ...  Execute Command
    ...  ps ax | grep ${pid} | grep -v grep
    ...  return_stdout=False  return_rc=True

    Return From Keyword If   '${rc}' == '${1}'
    ...   No obmc-console-client process running

    ${console}  ${stderr}=
    ...  Execute Command   kill -s KILL ${pid}
    ...  return_stderr=True
    Should Be Empty     ${stderr}
    Log  Current Client PID:${pid}

    ${console}  ${stderr}=
    ...  Execute Command
    ...  cat ${file_path}-${LOG_TIME}_${pid}
    ...  return_stderr=True
    Should Be Empty     ${stderr}

    [Return]    ${console}


Get Time Stamp
    [Documentation]     Get the current time stamp data
    ${cur_time}=    Get Current Date   result_format=%Y%m%d%H%M%S%f
    [return]   ${cur_time}


Verify BMC State
    [Documentation]   Get the BMC state and verify if the current
    ...               BMC state is as expected.
    [Arguments]       ${expected}

    ${current}=  Get BMC State
    Should Contain  ${current}   ${expected}

