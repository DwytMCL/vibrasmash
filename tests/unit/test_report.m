function tests = test_report
%TEST_REPORT Unit tests for the CSV writers and file hashing (src/report).
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

function testCsvWriterTypesNaNAndQuoting(~)
S.name = {'a'; 'b,c'; 'say "hi"'};
S.value = [1.5; NaN; 1e-7];
S.ok = [true; false; true];
f = [tempname() '.csv'];
c = onCleanup(@() delete(f));
vs_write_csv(f, S, {'ok', 'name', 'value'});
lines = read_lines(f);
assert(strcmp(lines{1}, 'ok,name,value'));
assert(strcmp(lines{2}, 'true,a,1.5'));
assert(strcmp(lines{3}, 'false,"b,c",'), 'NaN is an empty cell, never 0');
assert(strcmp(lines{4}, 'true,"say ""hi""",1e-07'));
end

function testCsvWriterRefusesRaggedColumns(~)
S.a = [1; 2];
S.b = {'x'};
f = [tempname() '.csv'];
try
    vs_write_csv(f, S);
    error('test:noError', 'Expected an error');
catch err
    assert(strcmp(err.identifier, 'vs_write_csv:length'), err.message);
end
end

function testFileHashIsSha256(~)
f = [tempname() '.txt'];
c = onCleanup(@() delete(f));
fid = fopen(f, 'w');
fwrite(fid, 'abc');
fclose(fid);
h = vs_file_hash(f);
% SHA-256('abc') from FIPS 180-2. 'unavailable' only when no hash
% implementation exists (MATLAB without Java).
assert(strcmp(h, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') || ...
    strcmp(h, 'unavailable'), 'Got %s', h);
end

function testSpectraCsvHasOneColumnPerComputedSpectrum(~)
res.shots.shot = [1; 2; 3];
res.shots.fft_computed = [true; false; true];
res.spectra.freq_hz = (0:4).' * 2.5;
res.spectra.amp = [ones(5, 1) nan(5, 1) 2 * ones(5, 1)];
f = [tempname() '.csv'];
c = onCleanup(@() delete(f));
vs_write_spectra_csv(f, res);
lines = read_lines(f);
assert(strcmp(lines{1}, 'freq_hz,amp_v_shot1,amp_v_shot3'));
assert(numel(lines) == 6 && strcmp(lines{3}, '2.5,1,2'));
end

function lines = read_lines(f)
txt = fileread(f);
lines = regexp(txt, '\r?\n', 'split');
lines = lines(~cellfun(@isempty, lines));
end
