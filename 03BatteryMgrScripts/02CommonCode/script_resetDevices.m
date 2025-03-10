% Disconnects both charger and discharger FIRST(This is IMPORTANT!!) before the relays
% if exist('psu','var')
%     if strcmpi(psu.SerialObj.Status, 'open')
%         psu.disconnect();
%     end
% end

try
    
    if caller == "gui"
        %% Caller == GUI
        %
        %     if exist('psu','var')
        %         if isvalid(psu)
        %             psu.disconnect();
        %             psu.SerialObj = [];
        %             clear('psu');
        %         end
        %     end
        %
        %
        %     if exist('eload','var')
        %         if isvalid(eload)
        %             eload.Disconnect();
        %             eload.SerialObj = [];
        %             clear('eload');
        %         end
        %     end
        %
        %     if exist('ljasm','var')
        %         relayState = false;
        %         if (isempty(ljasm) == 0)
        %             script_switchPowerDevRelays;
        %             ljudObj.AddRequestS(ljhandle,'LJ_ioPUT_DIGITAL_BIT', 4, 0, 0, 0);
        %             ljudObj.GoOne(ljhandle);
        %             ljudObj.Close();
        %             clear('ljudObj', 'ljasm');
        %         end
        %     end
        %
        %
        %     if exist('thermo','var')
        %         clear ('thermo');
        %     end
        %
        %     disp("Devices Reset" + newline);
        %
        %
    else
        
        %% Caller == Command Window
        
        %% Reset the Power Supply
        if exist('psu','var')
            if strcmpi(psu.serialStatus, 'Connected')
                psu.disconnect();
                [alarmState, alarm] = psu.getAlarmCode();
                if alarmState == true
                    warning("PSU Alarm state is True" + newline +...
                        "Alarm code is %s", alarm);
                    disp ("Attempting to clear alarm...")
                    reply = psu.ClearAlarmCode();
                    % If alarm is not cleared after an attempt notify user
                    if ~strcmpi("Alarm Cleared", reply)
                        notifyOwnerEmail("ATTENTION! Unable to clear PSU Alarm. Manual Override Required!!!")
                    else
                        disp(reply)
                    end
                end
                psu.disconnectSerial();
                clear('psu');
            end
        end
        
        %% Reset the Electronic Load
        if exist('eload','var')
            if strcmpi(eload.serialStatus, 'Connected')
                eload.Disconnect();
                [alarmState, alarm] = eload.getAlarmCode();
                if alarmState == true
                    warning("ELoad Alarm state is True" + newline +...
                        "Alarm code is %s", alarm);
                    disp ("Attempting to clear alarm...")
                    reply = eload.ClearAlarmCode();
                    % If alarm is not cleared after an attempt notify user
                    if ~strcmpi("Alarm Cleared", reply)
                        notifyOwnerEmail("ATTENTION! Unable to clear ELoad Alarm. Manual Override Required!!!")
                    else
                        disp(reply)
                    end
                end
                eload.disconnectSerial();
                clear('eload');
            end
        end
        
        %% Reset the LJ MCU
        if exist('ljasm','var')
            relayState = false;
            if (isempty(ljasm) == 0)
                if strcmpi(testSettings.voltMeasDev, "mcu")
                    LJ_MeasVolt = false;
                    [ljudObj,ljhandle] = MCU_digitalWrite(ljudObj, ljhandle, LJ_MeasVoltPin, LJ_MeasVolt, LJ_MeasVolt_Inverted);
                end
                script_switchPowerDevRelays;
                ljudObj.Close();
                clear('ljudObj', 'ljasm');
            end
        end
        
        %% Reset the DC2100A Balancer
        if exist('bal','var')
            if isvalid(bal) && strcmpi(bal.serialStatus, 'Connected')
                bal.disconnectSerial();
            end
        end
        
        %% Reset the Thermocouple module
        if exist('thermo','var')
            clear ('thermo');
        end
        
        %% Reset the Arduino Current Sensors
        
        if exist('ard','var')
            clear ('ard');
        end
        
        %% Notify user of reset state
        msg = "Devices Reset" + newline;
        if strcmpi(caller, "gui")
            send(randQ, msg);
        else
            disp(msg);
            disp("Test Ended on " + string(datetime('now')))
        end
        
    end
    
catch ME
    if strcmpi(caller, "gui")
        send(errorQ, ME);
    else
        rethrow(ME);
    end
end
