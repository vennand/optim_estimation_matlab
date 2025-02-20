function [prob, lbw, ubw, lbg, ubg] = GenerateEstimation_multiple_shooting(model, data)
import casadi.*

T = data.Duration; % secondes
Nint = data.Nint; % nb colloc nodes

dN = T/Nint;

[N_cardinal_coor, N_markers] = size(model.markers.coordinates);

tau_base = SX.zeros(6,1);
forDyn = @(x,u)[  x(model.idx_v)
    FDab_Casadi( model, x(model.idx_q), x(model.idx_v), vertcat(tau_base ,u)  )];
x = SX.sym('x', model.nx,1);
u = SX.sym('u', model.nu,1);
markers = SX.sym('markers', N_cardinal_coor, N_markers);
is_nan  = SX.sym('markers', N_cardinal_coor, N_markers);

L = @(x)base_referential_coor(model, x(1:model.NB)); % Estimated marker positions, not objective function
S = @(u)data.weightU * (u'*u);

f = Function('f', {x, u}, {forDyn(x,u)});
fJu = Function('fJ', {u}, {S(u)});
fJmarkers = Function('fJ', {x, markers, is_nan}, {data.weightPoints * objective_func(model,markers,is_nan,L(x))});

markers = data.markers;
is_nan = double(isnan(markers));

% Start with an empty NLP
w={};
lbw = [];
ubw = [];
J = 0;
g={};
lbg = [];
ubg = [];

Xk = MX.sym(['X_' '0'], model.nx);
w = {w{:}, Xk};
lbw = [lbw; model.xmin];
ubw = [ubw; model.xmax];

J = J + fJmarkers(Xk, markers(:,:,1), is_nan(:,:,1));

M = 4;
DT = dN/M;
for k=0:Nint-1
    Uk = MX.sym(['U_' num2str(k)], model.nu);
    w = {w{:}, Uk};
    lbw = [lbw; model.umin];
    ubw = [ubw; model.umax];
    
    for j=1:M
        k1 = f(Xk, Uk);
        k2 = f(Xk + DT/2 * k1, Uk);
        k3 = f(Xk + DT/2 * k2, Uk);
        k4 = f(Xk + DT * k3, Uk);

        Xk=Xk+DT/6*(k1 +2*k2 +2*k3 +k4);
    end
    
    Xkend = Xk;
    
    J = J + fJu(Uk);
    J = J + fJmarkers(Xk, markers(:,:,k+2), is_nan(:,:,k+2));
    
    Xk = MX.sym(['X_' num2str(k+1)], model.nx);
    w = {w{:}, Xk};
    lbw = [lbw; model.xmin];
    ubw = [ubw; model.xmax];
    
    g = {g{:}, Xkend - Xk};
    lbg = [lbg; zeros(model.nx,1)];
    ubg = [ubg; zeros(model.nx,1)];
end

prob = struct('f', J, 'x', vertcat(w{:}), 'g', vertcat(g{:}));

end
