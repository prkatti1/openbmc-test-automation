*** Settings ***
Documentation   This testsuite updates the PNOR image on the host for
...             hostboot CI purposes.

Resource        ../lib/utils.robot
Resource        ../lib/connection_client.robot

*** Variables ***

*** Test Cases ***

Host BIOS Update And Boot
    [Tags]    open-power
    [Documentation]   This test updates the PNOR image on the host (BIOS), and
    ...               validates that hosts boots normally.
    Reach System Steady State
    Update PNOR Image
    Validate IPL

*** Keywords ***

Reach System Steady State
    [Documentation]  Reboot the BMC, power off the Host and clear any previous
    ...              events
    Trigger Warm Reset
    Initiate Power Off
    Clear BMC Record Log

Update PNOR Image
    [Documentation]  Copy the PNOR image to the BMC /tmp dir and flash it.
    Copy PNOR to BMC
    ${pnor_path}    ${pnor_basename}=   Split Path    ${PNOR_IMAGE_PATH}
    Flash PNOR     /tmp/${pnor_basename}
    Wait Until Keyword Succeeds  7 min    10 sec    Is PNOR Flash Done

Validate IPL
    [Documentation]  Power the host on, and validate the IPL
    Initiate Power On
    Wait Until Keyword Succeeds  10 min    30 sec    Is System State Host Booted


