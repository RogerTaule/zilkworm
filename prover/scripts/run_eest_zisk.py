"""Run a directory of EEST JSON tests through the Zisk guest.

Each test:
  1. Read + minify JSON
  2. Wrap as [u64 LE total_len][is_test=1][minified_json][zero pad to 8]
  3. ziskemu -e <elf> -i <wrapped> -m
  4. Check exit code + presence of "passed" tokens vs "failed"/"FAILED"

Reports pass/fail per test + a final summary.
"""
import argparse, json, struct, pathlib, subprocess, sys, time, re, concurrent.futures, tempfile, os

def wrap_payload(json_path: pathlib.Path) -> bytes:
    raw = json_path.read_text()
    mini = json.dumps(json.loads(raw))
    body = b'\x01' + mini.encode('utf-8')
    pad = (-len(body)) % 8
    return struct.pack('<Q', len(body)) + body + b'\x00' * pad

def run_one(elf: str, json_path: pathlib.Path, timeout_s: int):
    try:
        wrapped = wrap_payload(json_path)
    except Exception as e:
        return (json_path, 'WRAP_FAIL', str(e), 0.0)
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as tf:
        tf.write(wrapped); tf.flush()
        bin_path = tf.name
    try:
        t0 = time.time()
        res = subprocess.run(
            ['ziskemu', '-e', elf, '-i', bin_path],
            capture_output=True, text=True, timeout=timeout_s,
        )
        elapsed = time.time() - t0
        text = res.stdout + res.stderr
        # The state_transition output reports "passed" / "failed" / "exception" per sub-test.
        # Count passes vs failures.
        passes = len(re.findall(r'\bpassed\b', text))
        fails  = len(re.findall(r'\b(failed|FAILED|exception|Exception)\b', text))
        if res.returncode != 0:
            status = 'CRASH'
        elif fails > 0:
            status = 'FAIL'
        elif passes == 0:
            status = 'NO_RESULT'
        else:
            status = 'OK'
        return (json_path, status, f'passes={passes} fails={fails}', elapsed)
    except subprocess.TimeoutExpired:
        return (json_path, 'TIMEOUT', f'>{timeout_s}s', timeout_s)
    finally:
        try: os.unlink(bin_path)
        except: pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--elf', required=True)
    ap.add_argument('--tests-dir', required=True)
    ap.add_argument('--timeout', type=int, default=60)
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--summary-only', action='store_true', help='print only summary lines, not per-test')
    args = ap.parse_args()

    tests = sorted(pathlib.Path(args.tests_dir).rglob('*.json'))
    print(f'discovered {len(tests)} tests under {args.tests_dir}', file=sys.stderr)
    counts = {'OK': 0, 'FAIL': 0, 'CRASH': 0, 'TIMEOUT': 0, 'NO_RESULT': 0, 'WRAP_FAIL': 0}
    t_start = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = [ex.submit(run_one, args.elf, t, args.timeout) for t in tests]
        for i, f in enumerate(concurrent.futures.as_completed(futs)):
            path, status, detail, elapsed = f.result()
            counts[status] += 1
            if not args.summary_only and status != 'OK':
                rel = path.relative_to(args.tests_dir)
                print(f'  [{status:9}] {rel}  ({detail}, {elapsed:.2f}s)')
            if (i + 1) % 25 == 0:
                done = i + 1
                rate = done / (time.time() - t_start + 0.001)
                eta = (len(tests) - done) / max(rate, 0.001)
                print(f'  ... {done}/{len(tests)} done, {rate:.1f} tests/s, ETA {eta:.0f}s', file=sys.stderr)

    elapsed = time.time() - t_start
    print()
    print(f'=== summary ({elapsed:.1f}s, {len(tests)} tests, {args.jobs} parallel) ===')
    for k, v in counts.items():
        pct = 100.0 * v / max(len(tests), 1)
        print(f'  {k:9}: {v:5d}  ({pct:5.1f}%)')
    overall = (counts['OK']) / max(len(tests), 1) * 100
    print(f'pass rate: {overall:.1f}%')

if __name__ == '__main__':
    main()
