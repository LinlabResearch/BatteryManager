function [testData, metadata, testSettings] = P06_SeriesPack_FC_HW(targSOC, chargeCurr, battID, varargin)
%chargeToSOC Charges to the specified SOC based on the charge current
%specified
%
%   Inputs: 
%       targSOC             : Target SOC to charge for
%      	chargeCurr          : Current (A) to charge
%       battID       		: ID of Cell/Pack being tested.
%       varargin   
%			trig1         	= false,  		: Accepts a Command to use the trigger activate something such as a heat pad
%			trig1_pin     	= 4,      		: Specifies what pin on the MCU to use(Initially used on a LABJack U3-HV)
%			trig1_startTime	= [10.0], 		: How long into the parent function to trigger. Can be an array of times (s)
%			trig1_duration	= [2.0],  		: How long should the trigger last
%											
%			caller      	= "cmdWindow", 	: Specifies who the parent caller is. The GUI or MatLab's cmd window. Implementations between both can be different
%			psuArgs       	= [],     		: Connection details of the power supply
%			eloadArgs     	= [],     		: Connection details of the Electronic Load
%			tempModArgs    	= [],     		: Connection details of the Temperature measuring module
%			sysMCUArgs     	= [],     		: Connection details of the Data Acquisition System. (Switches Relays and obtaines measurements)
%			saveArgs     	= [],     		: Arguments from the GUI used to save Data results
%			stackArgs     	= [],     		: Arguments from the GUI about the cells to be tested
%			dataQ         	= [],     		: Pollable DataQueue for real-time data transfer between 
%                                               2 parallel-run programs such as the function and GUI
%			errorQ        	= [],     		: Pollable DataQueue for real-time error data (exceptions) 
%                                               transfer between 2 parallel-run programs such as the function and GUI
%			randQ        	= [],     		: Pollable DataQueue for miscellaneous data (e.g confirmations etc) 
%                                               transfer between 2 parallel-run programs such as the function and GUI
%			testSettings  	= [];    		: Settings for the test such as cell configuration, sample time, data to capture etc
%
%   Outputs:
%       testData            : Struct of Test Data
%       metadata            : Test MetaData such as starttime, Tested Batt etc
%       testSettings        : Device, data measurement, and other settings
%                               to allow the functioning of the test

%% Parse Input Argument or set Defaults

param = struct(...
    'trig1',            false,  ... % General to most functions
    'trig1_pin',        4,      ... %           "
    'trig1_startTime',  [10.0], ... %           "
    'trig1_duration',   [2.0],  ... %           "
                    ...             %           "
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
    'testSettings',     struct...
                        ("cellConfig", "SerPar",...
                        "currMeasDev", "balancer",...
                        "tempChnls", [9, 10, 11, 12, 13]), ... %           " 
    'eventLog',         []);        % -------------------------

%% Evaluate Optional Parameters
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
eventLog = param.eventLog;


% If battID is not provided or is an empty string, make user provide it via
% a dialog box
if battID == "" || nargin < 3
    answer = inputdlg("Enter Battery ID. Case Insensitive.",'Battery ID not provided',[1 55],{'AE0'});
    if isempty(answer)
        return;
    else
        battID = string(answer{1});
    end
end
battID = upper(battID);

%% Series-Pack Fast Charging
% By Joseph Ojo
% 
% This script fast charges a series pack WITHOUT managing the anode potential
% level (Fast Charging). It also uses the DC2100A active balancer to ensure  
% that each parallel module in the series stack is equally charged. 
% Both bal_charge and bal_discharge are used.

%% Change Current Directory

% clearvars;
%
% currFilePath = mfilename('fullpath');
% [mainPath, filename, ~] = fileparts(currFilePath);
% cd(mainPath)

% clearvars -except bal eventLog; clc


%% Initialize Variables and Devices
try
    codeFilePath = mfilename('fullpath');
    % Seperates the path directory and the filename
    [codePath, codeFileName, ~] = fileparts(codeFilePath);

    str = extractBefore(codePath, "03BatteryMgrScripts");
    testSettings.saveDir = str + "00ProjectData\" + extractBefore(codeFileName, 4) + "\";

    testSettings.saveName   = "00SP_HCFC_" + battID;
    testSettings.purpose    = "Test for the series stack health conscious charging algorithm";
    testSettings.trigPins = []; % Find in every pin that should be triggered
    testSettings.trigInvert = []; % Fill in 1 for every pin that is reverse polarity (needs a zero to turn on)
    testSettings.trigStartTimes = {[100]}; % cell array of vectors. each vector corresponds to each the start times for each pin
    testSettings.trigDurations = {15}; % cell array of vectors. each vector corresponds to each the duration for each pin's trigger
    
    script_initializeVariables; % Run Script to initialize common variables

    if isempty(eventLog) || ~isvalid(eventLog) % ~exist('eventLog', 'var') || 
        eventLog = EventLogger();
    end
    
    script_initializeDevices; % Run Script to initialize control devices
%     verbosity = 1; % Data measurements are fully displayed.
%     verbosity = 2; % Data measurements are not displayed since the results from the MPC will be.
    balBoard_num = 0; % ID for the main balancer board
    
    MAX_CELL_VOLT = batteryParam.maxVolt(battID)/numCells_Ser;
    MIN_CELL_VOLT = batteryParam.minVolt(battID)/numCells_Ser;

%     wait(2); % Wait for the EEprom Data to be updated

    % Set Balancer Voltage Thresholds
    bal.Set_OVUV_Threshold(MAX_CELL_VOLT(1, 1), MIN_CELL_VOLT(1, 1));
    wait(1);

catch ME
    script_handleException;
end   


%% Constants
P06_Constants;
ANPOT_Target = -inf;  % Anode Potential has to be greater than 0 to ensure no lithium deposition
ANPOT_Target_BAL = -inf; % 0.05; % Anode Potential has to be greater than 0 to ensure no lithium deposition

% Function inputs
TARGET_SOC = targSOC;
testSettings.TARGET_SOC = TARGET_SOC;
MIN_CELL_CURR = -abs(chargeCurr); % Negative current means charging

ExpName = "FC_Main";


%% Predictive Model

% SOC Deviation Matrix
% 3 SOC Differences
%     L2 = [zeros(NUMCELLS-1, 1), (-1 * eye(NUMCELLS-1))];
%     L1 = eye(NUMCELLS);
%     L1(end, :) = [];
%     devMat = L1 + L2;

% 4 SOC Differences
L2 = [zeros(NUMCELLS, 1), (-1 * eye(NUMCELLS))];
L2(:, 1) = L2(:, end); L2(:, end) = [];
L1 = eye(NUMCELLS);
devMat = L1 + L2;
socMdl.devMat = devMat;

% What kind of balancing to use? mean SOC or devMat
socDevType = "mean";
% socDevType = "devMat";
socMdl.socDevType = socDevType;

P06_PredMdl;
predMdl.Volt = voltMdl;
predMdl.Temp = tempMdl;
predMdl.SOC = socMdl;
predMdl.Curr = currMdl;
predMdl.ANPOT = anPotMdl;

%% Initialize Plant variables and States 
% #############  Initial States  ##############
try
    verbosity = 1; % Allow initial battery data to be displayed
    script_queryData; % Get initial states from device measurements.
%     verbosity = 0; % Prevent battery measurements to be shown every single time
catch ME
    script_handleException;
end

Tf = thermoData(1); % Ambient Temp
tempMdl.Tf = Tf; % Ambient Temp
predMdl.Temp = tempMdl;


% Using OCV vs SOC to initialize the cell SOCs based on their resting voltages
[~, minIndSOC] = min(  abs( OCV - testData.cellVolt(end, :) )  );
%Using SOC gotten from OCV data (assuming battery pack has had a long rest
initialSOCs = SOC(minIndSOC, 1); 
testData.cellSOC(end, :) = initialSOCs;

% % Using SOC stored from previous test
% initialSOCs = testData.cellSOC(end, :)';

ANPOT = qinterp2(-predMdl.ANPOT.Curr, predMdl.ANPOT.SOC, predMdl.ANPOT.ANPOT,...
            zeros(NUMCELLS, 1), initialSOCs)';
testData.AnodePot = ANPOT; % Initialize AnodePot Structure field
testData.Ts             = thermoData(2:end);    % Initialize surface temperature to surf Temp
testData.Tc             = testData.Ts;    % Initialize core temperature to surf Temp


ind = 1;
xk = zeros(nx, 1);

xk(ind:ind+NUMCELLS-1, :)   =  testData.cellSOC(end, :)'; ind = ind + NUMCELLS;
xk(ind:ind+NUMCELLS-1, :)   =  zeros(1, NUMCELLS)'   ; ind = ind + NUMCELLS; % V1 - Voltage accross RC1
xk(ind:ind+NUMCELLS-1, :)   =  zeros(1, NUMCELLS)'   ; ind = ind + NUMCELLS; % V2 - Voltage accross RC2
xk(ind:ind+NUMCELLS-1, :)   =  testData.Tc'          ; ind = ind + NUMCELLS;
xk(ind:ind+NUMCELLS-1, :)   =  testData.Ts'          ; ind = ind + NUMCELLS;

testData.Cost = 0;
testData.ExitFlag = 0;
testData.Iters = 0;
testData.optBalCurr = zeros(1, NUMCELLS);
testData.optPSUCurr = zeros(1, NUMCELLS);
testData.predStates = xk(:)';
testData.predOutput = [testData.cellSOC(end, :), testData.Ts, testData.AnodePot];
testData.sTime = 0;
testData.SOC_Traj = testData.cellSOC(end, :);

%% MPC - Configure Parameters
try
    mpcObj = nlmpc(nx,ny,nu);
    
    p1 = sampleTime;        % Algorithm sample time
    p2 = predMdl;           % Predictive Battery Model Structure
    p3 = cellData;          % Constant Cell Data
    p4 = indices;           % Indices for the STATES (x)and OUTPUTS (y) presented as a struts
    
    mpcObj.Model.NumberOfParameters = 4; % dt and capacity
    
    mpcObj.Ts = sampleTime;
    mpcObj.PredictionHorizon = PH; % PH initialized in P06_Constants
    mpcObj.ControlHorizon = CH;
    
    % Constraints
    % Add Manipulated variable constraints
    % Small Rates affect speed a lot
    for i = 1:NUMCELLS
        mpcObj.MV(i).Max =  MAX_BAL_CURR;    mpcObj.MV(i).RateMax =  0.5; % MAX_CELL_CURR;
        mpcObj.MV(i).Min =  MIN_BAL_CURR;    mpcObj.MV(i).RateMin = -0.5; % -2; % -6
    end % MIN_BAL_CURR
    
    mpcObj.MV(NUMCELLS + 1).Max =  0;
    mpcObj.MV(NUMCELLS + 1).Min = (MIN_CELL_CURR + MAX_BAL_CURR); % MIN_PSUCURR_4_BAL; % 
    mpcObj.MV(NUMCELLS + 1).RateMax =  2; % MAX_CELL_CURR;
    mpcObj.MV(NUMCELLS + 1).RateMin = -2; % -6
    
    % Equality Limits for state/output vars for each cell
    for i=1:NUMCELLS
        % SOC
        mpcObj.States(i + (xSOC-1) * NUMCELLS).Max =  0.99;
        mpcObj.States(i + (xSOC-1) * NUMCELLS).Min =  0;
        
        % Ts
        mpcObj.States(i + (xTs-1) * NUMCELLS).Max =  44;
        mpcObj.States(i + (xTs-1) * NUMCELLS).Min =  0;
        mpcObj.States(i + (xTs-1) * NUMCELLS).ScaleFactor =  44;
        
        % Optimal Cell Curr
        mpcObj.States(i + (xCurr-1) * NUMCELLS).Max =  0;
        mpcObj.States(i + (xCurr-1) * NUMCELLS).Min =  -RATED_CAP;
        
        % ANPOT
%         mpcObj.OV(i + (yANPOT-1) * NUMCELLS).Max =  inf;
        mpcObj.OV(i + (yANPOT-1) * NUMCELLS).Min =  ANPOT_Target_BAL;
        mpcObj.OV(i + (yANPOT-1) * NUMCELLS).ScaleFactor =  1;
        mpcObj.OV(i + (yANPOT-1) * NUMCELLS).MinECR =  0;
        mpcObj.OV(i + (yANPOT-1) * NUMCELLS).MaxECR =  0;
    
    end
    
    %% MPC Reference Functions
    % Add dynamic model for nonlinear MPC
    mpcObj.Model.StateFcn = @(x, u, p1, p2, p3, p4)...
        P06_BattStateFcn_HW(x, u, p1, p2, p3, p4);
    mpcObj.Jacobian.StateFcn = @(x,u,p1, p2, p3, p4) ...
        P06_BattStateJac_HW(x, u, p1, p2, p3, p4);
    
    mpcObj.Model.OutputFcn = @(x,u, p1, p2, p3, p4) ...
        P06_OutputFcn_HW(x, u, p1, p2, p3, p4); % SOC, Volt, Ts
    mpcObj.Jacobian.OutputFcn = @(x,u,p1, p2, p3, p4) ... 
        P06_OutputJac_HW(x, u, p1, p2, p3, p4);
    
    mpcObj.Optimization.CustomCostFcn = @(X,U,e,data, p1, p2, p3, p4)...
        P06_CostFcn_HW(X, U, e, data, p1, p2, p3, p4);
%     mpcObj.Jacobian.CustomCostFcn = @(x,u,e,data, p1, p2, p3, p4) ...
%         P06_CostJac_HW(x, u,e,data, p1, p2, p3, p4);
    
    mpcObj.Optimization.CustomIneqConFcn = @(X,U,e,data, p1, p2, p3, p4)...
        P06_IneqConFcn_HW(X,U,e,data, p1, p2, p3, p4);
    mpcObj.Jacobian.CustomIneqConFcn = @(x,u,e,data, p1, p2, p3, p4) ...
        P06_IneqConJac_HW(x, u,e,data, p1, p2, p3, p4);
    
    %% Other MPC Settings
    mpcObj.Optimization.ReplaceStandardCost = true;
    
    mpcObj.Model.IsContinuousTime = false;
    
    mpcObj.Optimization.SolverOptions.UseParallel = true;
    
    mpcObj.Optimization.UseSuboptimalSolution = true;
    
    mpcObj.Optimization.SolverOptions.MaxIterations = 150; % 20; %
    
    mpcinfo = [];
    
    % SOC tracking, ANPOT tracking, and temp rise rate cuz refs have to equal number of outputs
    references = [repmat(TARGET_SOC, 1, NUMCELLS), zeros(1, NUMCELLS), zeros(1, NUMCELLS)];
    
    u0 = [zeros(1, NUMCELLS), 0];

    validateFcns(mpcObj, xk, u0, [], {p1, p2, p3, p4}, references);
catch ME
    script_handleException;
end

%% Parallel Pool
if USE_PARALLEL == true
    pool = gcp('nocreate');
    % Start Parallel Pool if it doesn't exist
    if isempty(pool)
        pool = parpool(1);
    end
end

%% Extended Kalman Filter Configuration
P06_EKF;

%% MPC Simulation

u = zeros(NUMCELLS + 1,1);
combCurr = zeros(NUMCELLS, 1);
optBalCurr = zeros(NUMCELLS, 1);

options = nlmpcmoveopt;
options.Parameters = {p1, p2, p3, p4};

mpcTimer = tic;
mpcRunning = false;
poolState = 'finished';

% ONLY_CHRG_FLAG = true;
ONLY_CHRG_FLAG = false;


try     
%% Some more initializations for the first time running the MPC
    sTime = [];readTime = [];
    tElapsed_plant = 0; prevStateTime = 0; prevMPCTime = 0;
    SOC_Traj = []; debugData = struct("xk", [], "u", []); ExitFlag = 0;
    DfltMinPSUVal = mpcObj.MV(NUMCELLS + 1).Min;
    mdl_X = P06_BattStateFcn_HW(xk, u, p1, p2, p3, p4);
    y_Ts = thermoData(2:end);
    y = [ testData.cellVolt(end, :),  y_Ts(:)', ANPOT(:)'];
     
    
    if ONLY_CHRG_FLAG == false...
            &&(max(testData.cellSOC(end, :) > MAX_BAL_SOC) ... % If at least one cell is  > MAX_BAL_SOC || < MIN_BAL_SOC
            || max(testData.cellSOC(end, :) < MIN_BAL_SOC))...
            || abs( max(xk(xIND.SOC)) - min(xk(xIND.SOC)) ) < ALLOWABLE_SOCDEV
        
        BalanceCellsFlag = false; % Out of range Balancing SOC flag - Flag to set when SOC is greater/less than range for balancing
        predMdl.Curr.balWeight = 0;
        p2 = predMdl;
        options.Parameters = {p1, p2, p3, p4};
    elseif max(testData.cellSOC(end, :) < MAX_BAL_SOC) ... % If all cells are > MIN_BAL_SOC && < MAX_BAL_SOC
            && min(testData.cellSOC(end, :) > MIN_BAL_SOC)
        
        % If any of the cells are close to max voltage,
        % manually reduce the PSU current limit.
        % This is really not ideal, the mpc should be able to
        % figure this out itself
        if max(testData.cellVolt(end, :) > 3.85) && max(testData.cellSOC(end, :) > MAX_BAL_SOC)
            mpcObj.MV(NUMCELLS + 1).Min = MIN_PSUCURR_4_HIVOLTBAL; % + max(testData.cellSOC(end, :));
        else
            mpcObj.MV(NUMCELLS + 1).Min = DfltMinPSUVal;
        end
        BalanceCellsFlag = true; % Out of range Balancing SOC flag - Flag to set when SOC is greater/less than range for balancing
        predMdl.Curr.balWeight = 1;
    end
    
%% Main Loop  
    while testData.packSOC(end, :) <= TARGET_SOC ...
            && ~strcmpi(testStatus, "stop")  
        
        if ( toc(testTimer)- prevMPCTime ) >= sampleTime && strcmpi(poolState, "finished")
            tElapsed_MPC = toc(testTimer);
            actual_STime = tElapsed_MPC - prevMPCTime;
            prevMPCTime = tElapsed_MPC;

            %% Prepare data for MPC input
            P06_PrepareMPCInput;
            
            %% Run the MPC controller
            if USE_PARALLEL == true
                mpcFeval = parfeval(pool,@nlmpcmove, 3, mpcObj,  xk, u,...
                    references,[], options);
            else
                [u,~,mpcinfo] = nlmpcmove(mpcObj, xk, u,...
                    references,[], options); % (:,idx-1)
            end

            mpcRunning = true;
        end
        
        if exist('mpcFeval', 'var') || USE_PARALLEL == false
            if USE_PARALLEL == true, poolState = mpcFeval.State; end
            if strcmpi(poolState, "finished") && mpcRunning == true
                if USE_PARALLEL == true
                    [u,~,mpcinfo] = fetchOutputs(mpcFeval,'UniformOutput',false);
                    u = u{:};
                    mpcinfo = mpcinfo{:};
                end
                mpcRunning = false;
                
                mdl_X = P06_BattStateFcn_HW(xk, u, p1, p2, p3, p4);
                mdl_Y = P06_OutputFcn_HW(mdl_X, u, p1, p2, p3, p4)';
                
                optCurr = u; % u<0 == Charging, u>0 == discharging
                cost = mpcinfo.Cost;
                iters = mpcinfo.Iterations;

                % Balancer and PSU Current
                optBalCurr = optCurr(1:NUMCELLS);
                optPSUCurr = optCurr(end);
                
                
                % Set power supply current
                curr = abs(optPSUCurr); % PSU Current. Using "curr" since script in nect line uses "curr"
                script_charge;
                               
                % Disable Balancing if SOC is past range. MPC won't optimize
                % for Balance currents past this range
                if BalanceCellsFlag == true                    
                    % send balance charges to balancer
                    bal.SetBalanceCharges(balBoard_num, optBalCurr*sampleTime); % Send charges in As
                else
                    bal.Currents(balBoard_num +1, logical(bal.cellPresent(1, :))) = zeros(size(optBalCurr));
                end
                
                tElapsed_plant = toc(testTimer);
                
%                 % Combine the PSU and BalCurr based on the balancer transformation
%                 % matrix
%                 combCurr = combineCurrents(optPSUCurr, optBalCurr, predMdl);
                
                wait(0.05);
                
                prevElapsed = tElapsed_plant;
                
            end
        end

               
        % Record Data from devices
        P06_RecordData;
        
        % curr > 0 = Discharging
        if (max(combCurr > 0 & xk(1+NUMCELLS*(xIND.SOC-1):NUMCELLS*xIND.SOC, :) <= 0.01))...
                || (max(combCurr < 0 & xk(1+NUMCELLS*(xIND.SOC-1):NUMCELLS*xIND.SOC, :) >= 0.99))
            disp("Test Overcharged after: " + tElapsed_plant + " seconds.")
            break;
        end
                
    end
    
    script_resetDevices;
    disp("Test Completed After: " + tElapsed_plant + " seconds.")

%% Save Test Data
    P06_SaveTestData;

catch ME
%     dataQueryTimerStopped();
    script_handleException;
end

end
