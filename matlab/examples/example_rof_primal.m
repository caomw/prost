%%
% load input image
im = imread('../../images/dog.png');
[ny, nx, nc] = size(im);
f = double(im(:)) / 255.; % convert to [0, 1]

%%
% parameters
grad = spmat_gradient2d(nx,ny,nc);
lmb = 0.3;

%%
% problem
u = prost.variable(nx*ny*nc);
g = prost.variable(2*nx*ny*nc);

% Example on how to use sub-variables:
u1 = prost.sub_variable(u, 100);
u2 = prost.sub_variable(u, 500);
u3 = prost.sub_variable(u, nx*ny*nc-600);
u1.fun = prost.function.sum_1d('square', 1, f(1:100), lmb, 0, 0);
u2.fun = prost.function.sum_1d('square', 1, f(101:600), lmb, 0, 0);
u3.fun = prost.function.sum_1d('square', 1, f(601:end), lmb, 0, 0);

g.fun = prost.function.sum_norm2(2 * nc, false, 'abs', 1, 0, 1, 0, 0);

prost.set_constraint(u, g, prost.linop.sparse(grad));
prob = prost.min( {u}, {g} );

%%
% specify solver options
backend = prost.backend.pdhg('stepsize', 'boyd', ...
                             'residual_iter', 1, ...
                             'alg2_gamma', 0.05 * lmb);

pd_gap_callback = @(it, x, y) example_rof_pdgap(it, x, y, grad, ...
                                                f, lmb, ny, nx, nc);

opts = prost.options('max_iters', 1000, ...
                     'interm_cb', pd_gap_callback, ...
                     'num_cback_calls', 25, ...
                     'verbose', true);

tic;
result = prost.solve(prob, backend, opts);
toc;

%%
% show result
imshow(reshape(u.val, [ny nx nc]));
