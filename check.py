from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import subprocess
import tempfile


PROGRAM = Path(__file__).with_name("program").resolve()


def run(directory, *, user=None):
    return subprocess.run(
        [str(PROGRAM)], cwd=directory, capture_output=True, timeout=5, user=user
    )


def check():
    passed = 0
    with tempfile.TemporaryDirectory(prefix="visit-counter-") as directory:
        root = Path(directory)
        count = root / "count.txt"

        def success(expected):
            nonlocal passed
            result = run(root)
            assert result.returncode == 0, result.stderr
            assert result.stdout == f"Visits: {expected}\n".encode(), result.stdout
            assert result.stderr == b"", result.stderr
            assert count.read_bytes() == f"{expected}\n".encode()
            passed += 1

        def failure():
            nonlocal passed
            original = count.read_bytes()
            result = run(root)
            assert result.returncode == 1, result.returncode
            assert result.stdout == b"", result.stdout
            assert result.stderr.startswith(b"Error: "), result.stderr
            assert count.read_bytes() == original
            passed += 1

        print("Missing count.txt; three independent launches:")
        for value in (1, 2, 3):
            success(value)
            print(f"  Visits: {value}; count.txt = {value}")

        for original, expected in (
            (b"", 1),
            (b"0", 1),
            (b"9\n", 10),
            (b"99", 100),
            (b"999\n", 1000),
            (b"00000000000000000009\n", 10),
            (b"1234567890123456789\n", 1234567890123456790),
            (b"18446744073709551614\n", 18446744073709551615),
        ):
            count.write_bytes(original)
            success(expected)
            print(f"  {original!r} -> {expected}")

        print("Invalid input and overflow are rejected without changing the file:")
        for original in (
            b"abc\n", b"-1\n", b"1x\n", b"\n", b"1\n2\n", b" 3\n",
            b"1\x00", b"1\r\n", b"9" * 32, b"0" * 100,
            b"18446744073709551615\n", b"18446744073709551616\n",
        ):
            count.write_bytes(original)
            failure()
            print(f"  {original!r}: rejected; unchanged")

        count.unlink()
        count.mkdir()
        result = run(root)
        assert result.returncode == 1 and result.stderr.startswith(b"Error: ")
        assert count.is_dir() and not result.stdout
        count.rmdir()
        passed += 1
        print("  count.txt is a directory: handled")

        if os.geteuid() == 0:
            root.chmod(0o755)
            count.write_bytes(b"7\n")
            count.chmod(0o444)
            result = run(root, user=65534)
            assert result.returncode == 1 and result.stderr.startswith(b"Error: ")
            assert not result.stdout and count.read_bytes() == b"7\n"
            count.chmod(0o644)
            passed += 1
            print("  read-only file (unprivileged user): handled; unchanged")

        count.write_bytes(b"7\n")
        with open("/dev/full", "wb") as full:
            result = subprocess.run(
                [str(PROGRAM)], cwd=root, stdout=full, stderr=subprocess.PIPE, timeout=5
            )
        assert result.returncode == 1 and result.stderr.startswith(b"Error: ")
        assert count.read_bytes() == b"8\n"
        passed += 1
        print("  stdout write failure: reported; saved count.txt = 8")

        count.write_text("0\n")
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: run(root), range(40)))
        assert all(r.returncode == 0 and not r.stderr for r in results)
        values = sorted(int(r.stdout.removeprefix(b"Visits: ")) for r in results)
        assert values == list(range(1, 41)), values
        assert count.read_bytes() == b"40\n"
        passed += 1
        print("  40 concurrent launches: values 1..40; count.txt = 40")

    print(f"PASS: {passed} checks")


if __name__ == "__main__":
    check()
