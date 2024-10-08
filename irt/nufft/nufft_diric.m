  function f = nufft_diric(k, N, K, use_true_diric)
%|function f = nufft_diric(k, N, K, use_true_diric)
%|
%| "regular fourier" Dirichlet-function WITHOUT phase
%| diric(t) = sin(pi N t / K) / ( N * sin(pi t / K) )
%|	\approx sinc(t / (K/N))
%|
%| caution: diric() is K-periodic if N is odd but 2K-periodic if N is even.
%|
%| in
%|	k [...]		sample locations (unitless real numbers)
%|	N		signal length
%|	K		DFT length
%|	use_true_diric	1 = use true Diric function.
%|			(default is to use sinc approximation)
%| out
%|	f [...]		corresponding function values
%|
%| Copyright 2001-12-8, Jeff Fessler, The University of Michigan

if nargin == 1 && streq(k, 'test'), nufft_diric_test, return, end
if nargin < 3, help(mfilename), error(mfilename), end

if nargin < 4
	use_true_diric = false;
end

% diric version
if use_true_diric
	t = (pi/K) * k;
	f = sin(t);
	i = abs(t) > 1e-12;	% nonzero argument
	f(i) = sin(N*t(i)) ./ (N * f(i));
	f(~i) = 1;

% sinc version
else
	f = nufft_sinc(k / (K/N));
end

function nufft_diric_test
kmax = 2 * (10 + 1 * 4);
kf = linspace(-kmax,kmax,201); % fine grid
ki = [-kmax:kmax];
Nlist = [2^3 2^5 2^3-1];
Klist = 2*Nlist; Klist(end) = Nlist(end);
jf pl 3 1
for ii=1:length(Nlist)
	N = 0 + Nlist(ii);
	K = 0 + Klist(ii);
	gf = nufft_diric(kf, N, K, 1);
	gi = nufft_diric(ki, N, K, 1);
	sf = nufft_diric(kf, N, K);
	dm = diric((2*pi/K)*kf,N);
	jf('sub', ii)
	plot(kf, gf, 'y-', kf, sf, 'c-', kf, dm, 'r--', ki, gi, 'y.')
	axis tight
	if ii==1, xtick([-1 -0.5 0 0.5 1]*K), end
	legend('nufft diric', 'sinc', 'matlab diric')
	xlabel k, ylabel diric(k)
	printf('max %% difference = %g', max_percent_diff(gf,sf))
	titlef('N = %d, K = %d', N, K)
end
