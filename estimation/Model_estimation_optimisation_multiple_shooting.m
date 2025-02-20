% Script to optimize a trajectory with 42 DoF, 1sec time frame
% models with trapezoidal collocation
clear, clc, close all
tic
run('../startup.m')
import casadi.*

data.nDoF = 42;

data.Nint = 50;% number of control nodes
data.subject = 'DoCi';
data.odeMethod = 'rk4';
data.NLPMethod = 'MultipleShooting';

data.optimiseGravity = false;
data.gravity = [0; 0; -9.81];
data.gravityZBound = data.gravity;
data.gravityRotationBound = pi/16;

data.optimiseInertia = false; % In construction
data.inertiaTorsoRelativeBound = 0.1;

data.dataFile = '../data/Do_822_contact_2.c3d';
data.kalmanDataFile_q = '../data/Do_822_contact_2_MOD200.00_GenderF_DoCig_Q.mat';
data.kalmanDataFile_v = '../data/Do_822_contact_2_MOD200.00_GenderF_DoCig_V.mat';
data.kalmanDataFile_a = '../data/Do_822_contact_2_MOD200.00_GenderF_DoCig_A.mat';

data.optimisedKalman = true;
data.optimisedKalmanGravity = true;

% Spécific à Do_822_contact_2.c3d
% Le saut est entre les frames 3050 et 3386
% data.frames = 3078:3368; % Sans contact avec la trampoline
data.frames = 3100:3300; % Sans contact avec la trampoline, interval plus sévère
% data.frames = 3100:3200;
data.labels = 1:95;

data.realNint = length(data.frames);

data = adjust_number_of_interval(data);

data.weightU = 1e-7;
data.weightPoints = 1;

disp('Generating Model')
[model, data] = GenerateModel(data);
disp('Loading Kalman Filter')
[model, data] = GenerateKalmanFilter(model,data);
disp('Loading Real Data')
[model, data] = GenerateRealData(model,data);
disp('Calculating Estimation')
[prob, lbw, ubw, lbg, ubg, objFunc, conFunc, objGrad, conGrad] = GenerateEstimation_multiple_shooting(model, data);

% [lbw, ubw] = GenerateInitialConstraints(model, data, lbw, ubw);
% [lbw, ubw] = GenerateFinalConstraints(model, data, lbw, ubw);

options = struct;
options.ipopt.max_iter = 3000;
options.ipopt.print_level = 5;
options.ipopt.linear_solver = 'ma57';

options.ipopt.tol = 1e-5; % default: 1e-08
% options.ipopt.acceptable_tol = 1e-4; % default: 1e-06
options.ipopt.constr_viol_tol = 0.001; % default: 0.0001
% options.ipopt.acceptable_constr_viol_tol = 0.1; % default: 0.01

% options.ipopt.hessian_approximation = 'limited-memory';

disp('Generating Solver')
% solver = nlpsol('solver', 'snopt', prob, options); % FAIRE MARCHER ÇA
solver = nlpsol('solver', 'ipopt', prob, options);

w0=[];
for k=1:data.Nint
%     w0 = [w0;  data.x0];
    w0 = [w0;  data.kalman_q(:,k); data.kalman_v(:,k)];
%     w0 = [w0;  data.u0];
    w0 = [w0;  data.kalman_tau(:,k)];
end
% w0 = [w0;  data.x0];
w0 = [w0;  data.kalman_q(:,data.Nint+1); data.kalman_v(:,data.Nint+1)];

if data.optimiseGravity
    w0 = [w0;  data.gravity];
end

sol = solver('x0', w0, 'lbx', lbw, 'ubx', ubw, 'lbg', lbg, 'ubg', ubg);

q_opt = nan(model.nq,data.Nint+1);
v_opt = nan(model.nq,data.Nint+1);
u_opt = nan(model.nu,data.Nint);
w_opt = full(sol.x);

if data.optimiseGravity
    for i=1:model.nq
        q_opt(i,:) = w_opt(i:model.nx+model.nu:end-3)';
        v_opt(i,:) = w_opt(i+model.nq:model.nx+model.nu:end-3)';
    end
    for i=1:model.nu
        u_opt(i,:) = w_opt(i+model.nx:model.nx+model.nu:end-3)';
    end
    G_opt = w_opt(end-2:end);
    data.G_opt = G_opt;
else
    for i=1:model.nq
        q_opt(i,:) = w_opt(i:model.nx+model.nu:end)';
        v_opt(i,:) = w_opt(i+model.nq:model.nx+model.nu:end)';
    end
    for i=1:model.nu
        u_opt(i,:) = w_opt(i+model.nx:model.nx+model.nu:end)';
    end
end

data.q_opt = q_opt;
data.v_opt = v_opt;
data.u_opt = u_opt;

% disp('Calculating Simulation')
% [model, data] = GenerateSimulation(model, data);
disp('Calculating Momentum')
data = CalculateMomentum(model, data);

stats = solver.stats;
save(['Solutions/Do_822_F' num2str(data.frames(1)) '-' num2str(data.frames(end)) ...
      '_U' num2str(data.weightU) '_N' num2str(data.Nint) ...
      '_gravityRotationBound=' num2str(data.gravityRotationBound) ...
      '_optimisedKalman=' num2str(data.optimisedKalman) ...
      '_optimisedKalmanGravity' num2str(data.optimisedKalmanGravity) ...
      '_IPOPTMA57_.mat'],'model','data','stats')
% GeneratePlots(model, data);
% AnimatePlot(model, data, 'sol', 'mocap');
toc
% showmotion(model, 0:data.Duration/data.Nint:data.Duration, q_opt(:,:))
