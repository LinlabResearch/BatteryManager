function [testData, metadata, testSettings]  = waitTillTime(targTime, varargin)
%waitTillTime Idles the battery (pack) while waiting until the target time
%is up
%
%   Inputs: 
%       targSOC            : Target time to charge for
%      	chargeCurr          : Current (A) to charge
%       varargin   
%			trig1         	= false,  		: Accepts a Command to use the trigger activate something such as a heat pad
%			trig1_pin     	= 4,      		: Specifies what pin on the MCU to use(Initially used on a LABJack U3-HV)
%			trig1_startTime	= [10.0], 		: How long into the parent function to trigger. Can be an array of times (s)
%			trig1_duration	= [2.0],  		: How long should the trigger last
%											
%			battID       	= [],     		: IDs of Cells being tested. If parallel specify all cells in string array
%			caller      	= "cmdWindow", 	: Specifies who the parent caller is. The GUI or MatLab's cmd window. Implementations between both can be different
%			psuArgs       	= [],     		: Connection details of the power supply
%			eloadArgs     	= [],     		: Connection details of the Electronic Load
%			tempModArgs    	= [],     		: Connection details of the Temperature measuring module
%			sysMCUArgs     	= [],     		: Connection details of the Data Acquisition System. (Switches Relays and obtaines measurements)
%			sysMCUArgs     	= [],     		: Arguments from the GUI used to save Data results
%			saveArgs     	= [],     		: Arguments from the GUI used to save Data results
%			stackArgs     	= [],     		: Arguments from the GUI about the cells to be tested
%			dataQ         	= [],     		: Pollable DataQueue for real-time data transfer between 
%                                               2 parallel-run programs such as the function and GUI
%			errorQ        	= [],     		: Pollable DataQueue for real-time error data (exceptions) 
%                                               transfer between 2 parallel-run programs such as the function and GUI
%			randQ        	= [],     		: Pollable DataQueue for miscellaneous data (e.g confirmations etc) 
%                                               transfer between 2 parallel-run programs such as the function and GUI
%			testSettings  	= [];    		: Settings for the test such as cell configuration, sample time, data to capture etc
%			verbosity       = 0;    		: How often to display data on the command line
%                                               0: every 60 timesteps 
%                                               1: every timesteps 
%
%   Outputs:
%       testData            : Struct of Test Data
%       metadata            : Test MetaData such as starttime, Tested Batt etc
%       testSettings        : Device, data measurement, and other settings
%                               to allow the functioning of the test


%% Setup Code
try

    param = struct(...
    'trig1',            false,  ... % General to most functions
    'trig1_pin',        4,      ... %           "
    'trig1_startTime',  [10.0], ... %           "
    'trig1_duration',   [2.0],  ... %           "
                    ...             %           "
    'battID',          [],     ... %           "
    'caller',      "cmdWindow", ... %           "
    'psuArgs',          [],     ... %           "
    'eloadArgs',        [],     ... %           "
    'tempModArgs',      [],     ... %           "
    'balArgs',          [],     ... %           "
    'sysMCUArgs',       [],     ... %           "
    'saveArgs',         [],     ... %           "
    'stackArgs',        [],     ... %           "
    'dataQ',            [],     ... %           "
    'errorQ',           [],     ... %           "
    'randQ',            [],     ... %           "
    'testSettings',     [],     ... %           "
    'verbosity',         0,     ... %           " 
    'eventLog',         []);        % -------------------------


    % read the acceptable names
    paramNames = fieldnames(param);

    % Ensure variable entries are pairs
    nArgs = length(varargin);
    if round(nArgs/2)~=nArgs/2
        error('runProfile needs propertyName/propertyValue pairs')
    end

    for pair = reshape(varargin,2,[]) %# pair is {propName;propValue}
        inpName = pair{1}; %# make case insensitive

        if any(strcmpi(inpName,paramNames))
            %# overwrite options. If you want you can test for the right class here
            %# Also, if you find out that there is an option you keep getting wrong,
            %# you can use "if strcmp(inpName,'problemOption'),testMore,end"-statements
            param.(inpName) = pair{2};
        else
            error('%s is not a recognized parameter name',inpName)
        end
    end

    % ---------------------------------

    battID = param.battID;
    caller = param.caller;
    psuArgs = param.psuArgs;
    eloadArgs = param.eloadArgs;
    tempModArgs = param.tempModArgs;
    balArgs = param.balArgs;
    sysMCUArgs = param.sysMCUArgs;
    stackArgs = param.stackArgs;
    dataQ = param.dataQ;
    errorQ = param.errorQ;
    randQ = param.randQ;
    testSettings = param.testSettings;
    
    if (isempty(testSettings) || ~isfield(testSettings, 'trigPins')) ...
            && param.trig1 == true
        testSettings.trigPins = param.trig1_pin;
        testSettings.trigStartTimes = {param.trig1_startTime};
        testSettings.trigDurations = {param.trig1_duration};
        testSettings.trigInvert = zeros(length(param.trig1_startTime), 1);
    end
    
    if isfield(testSettings, 'trigPins') && ~isempty(testSettings.trigPins) % param.trig1 == true
        if length(testSettings.trigPins) == size(testSettings.trigStartTimes, 1) && ...
                length(testSettings.trigPins) == size(testSettings.trigDurations, 1)
            
            trigPins = testSettings.trigPins;
            trigStartTimes = testSettings.trigStartTimes;
            trigDurations = testSettings.trigDurations;
            trigInvert   = testSettings.trigInvert;
            trigTimeTol = 0.5; % Half a second
            for i = 1:length(trigPins)
                pins2(i) = {repmat(trigPins(i), 1, length(trigStartTimes{i}))};
                inverts2(i) = {repmat(trigInvert(i), 1, length(trigStartTimes{i}))};
            end
            pins = horzcat(pins2{:})';
            inverts = horzcat(inverts2{:})';
            startTimes = horzcat(trigStartTimes{:})';
            durations = horzcat(trigDurations{:})';
            endTimes = startTimes + durations;
            
            triggers = sortrows(table(pins, startTimes, durations, endTimes, inverts), 'startTimes', 'ascend');
            
            trigAvail = true;
            trig_Ind = 1;
            trig_On = false(length(pins) , 1);
            
        else
            err.code = ErrorCode.BAD_SETTING;
            err.msg = "The number of trigger pins and time inputs do not match." + newline + ...
                " Make sure to enter a start time and duration for each trigger pin.";
            send(errorQ, err);
        end
        
    else
        trigAvail = false;
    end
    
    
    
    disp("Waiting for " + num2str(targTime) + " Seconds!");
    
    script_initializeVariables;
    script_initializeDevices;

    verbose = param.verbosity;
    battState = "idle";
    
    testTimer = tic; % For sampling measured data
    
    script_queryData;
    script_failSafes; %Run FailSafe Checks
    if errorCode == 1 || strcmpi(testStatus, "stop")
        script_idle;
        return;
    end

    WaitTimer = tic;
    waitTicker = 0;
    
    while (waitTicker < targTime)
        waitTicker = toc(WaitTimer); % Counts up from zero
        
        if toc(testTimer) - timerPrev(3) >= readPeriod
            timerPrev(3) = toc(testTimer);
            script_queryData; % Runs the script that queries data from the devices. Stores the results in the [dataCollection] Variable
            script_failSafes; %Run FailSafe Checks
            script_checkGUICmd; % Check to see if there are any commands from GUI
            % if limits are reached, break loop
            if strcmpi(testStatus, "stop")
                script_idle;
                break;
            end
        end
        
        %% Triggers (GPIO from LabJack)
        script_triggerDigitalPins
    end
    
    disp("Waiting Done" + newline);
    
catch ME
    script_handleException;
end

script_resetDevices;

end
