% Checks to see if limits are reached
errorCode = repmat(ErrorCode.NO_ERROR, 1, numCells_Ser);
for cell_Ind = 1:numCells_Ser
    %     if cells.coreTemp(battID) > battCoreTempLimit
    %         error = sprintf("Core TEMP for " + cellID + " has Exceeded Limit:  %.2f ",...
    %             cells.coreTemp(battID));
    %         warning(error);
    %         clear('thermo');
    %         save(dataLocation + "007BatteryParam.mat", 'batteryParam');
    %         script_resetDevices
    %         waitTS = waitTillTemp('core','battID', battID, 'temp', 35);
    %         battTS = appendBattTS2TS(battTS, waitTS);
    %         script_initializeDevices;
    %         %     errorCode = 1;
    %     elseif cells.surfTemp(battID) > batteryParam.maxSurfTemp(battID)
    %         error = sprintf("Surface TEMP for " + battID + " has Exceeded Limit:  %.2f ", cells.surfTemp(battID));
    %         warning(error);
    %         clear('thermo');
    %         save(dataLocation + "007BatteryParam.mat", 'batteryParam');
    %         script_resetDevices;
    %         waitTS = waitTillTemp('surf','battID', battID, 'temp', 35);
    %         battTS = appendBattTS2TS(battTS, waitTS);
    %         script_initializeDevices;
    %         %     errorCode = 1;
    %     else
    if testData.cellVolt(end, cell_Ind) <= batteryParam.minVolt(battID)/numCells_Ser % Dividing by numCells in series since minVolt is for the series stack
%         script_queryData;
%         if testData.cellVolt(end, cell_Ind) <= batteryParam.minVolt(battID)/numCells_Ser % Dividing by numCells in series since minVolt is for the series stack
            error = sprintf("Battery VOLTAGE for Cell("+cell_Ind+", :) in " + battID + " is Less than Limit: %.2f V", testData.cellVolt(end, cell_Ind));
            warning(error);
            errorCode(cell_Ind) = ErrorCode.UV;
%             testStatus = "stop";
%         end
    elseif testData.cellVolt(end, cell_Ind) >= batteryParam.maxVolt(battID)/numCells_Ser % Dividing by numCells in series since maxVolt is for the series stack
%         script_queryData; % Check again
%         if testData.cellVolt(end, cell_Ind) >= batteryParam.maxVolt(battID)/numCells_Ser % Dividing by numCells in series since maxVolt is for the series stack
            error = sprintf("Battery VOLTAGE for Cell("+cell_Ind+", :) in " + battID + " is Greater than Limit: %.2f V", testData.cellVolt(end, cell_Ind));
            warning(error);
            errorCode(cell_Ind) = ErrorCode.OV;
            testStatus = "stop";
%         end
    elseif testData.cellCurr(end, cell_Ind) < batteryParam.minCurr(battID) %/numCells_Par % During Charge
        error = sprintf("Battery CURRENT for Cell("+cell_Ind+", :) in " + battID + " is Less than Limit: %.2f A", testData.cellCurr(end, cell_Ind));
        warning(error);
        errorCode(cell_Ind) = ErrorCode.UC;
        testStatus = "stop";
    elseif testData.cellCurr(end, cell_Ind) > batteryParam.maxCurr(battID) %/numCells_Par % During Discharge. Dividing here since maxCurr is for entire parallel stack
        error = sprintf("Battery CURRENT for Cell("+cell_Ind+", :) in " + battID + " is Greater than Limit: %.2f A", testData.cellCurr(end, cell_Ind));
        warning(error);
        errorCode(cell_Ind) = ErrorCode.OC;
        testStatus = "stop";
    elseif testData.cellSOC(end, cell_Ind) > 1.05 && trackSOCFS == true
        warning("Battery SOC for Cell("+cell_Ind+", :) in " + battID + " is Greater than 100%%:  %.2f%%",testData.cellSOC(end, cell_Ind)*100);
    elseif testData.cellSOC(end, cell_Ind) <= -0.005  && trackSOCFS == true
        warning("Battery SOC for Cell("+cell_Ind+", :) in " + battID + " is Less than 0%%:  %.2f%%",testData.cellSOC(end, cell_Ind)*100);
    end
end


[alarmState, alarm] = psu.getAlarmCode();
AL = 0;
if alarmState == true
    AL = AL+1;
    if AL <= 5
        warning("PSU AlarmState is True. Cause: " + alarm);
    end
    if AL == 1 || mod(AL, 100)==0 % Notify user every 100 times alarm remains
        notifyOwnerEmail("PSU AlarmState is True. Cause: " + alarm)
    end
end

if min(errorCode == ErrorCode.NO_ERROR) == 0
    % Save Battery Parameters
    save(dataLocation + "007BatteryParam.mat", 'batteryParam');

    notifyOwnerEmail(error)
end

