from pathlib import Path
import subprocess
import tempfile


def extract_thread_info_views(source: str) -> str:
    start_marker = "final class MutableMessageHistoryThreadInfoView:"
    end_marker = "public final class MessageHistoryThreadInfoView:"
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:] + "\n"


def main() -> None:
    test_root = Path(__file__).resolve().parent
    source_path = test_root.parents[1] / "submodules/Postbox/Sources/MessageHistoryThreadIndexView.swift"
    extracted_source = extract_thread_info_views(source_path.read_text())

    with tempfile.TemporaryDirectory(prefix="local-archive-thread-info-") as build_root:
        build_path = Path(build_root)
        extracted_path = build_path / "MessageHistoryThreadInfoViews.swift"
        extracted_path.write_text(extracted_source)
        output_path = build_path / "thread-info-tests"
        subprocess.run(
            [
                "swiftc",
                str(test_root / "MessageHistoryThreadInfoPostbox.swift"),
                str(extracted_path),
                str(test_root / "MessageHistoryThreadInfoTests.swift"),
                "-o",
                str(output_path),
            ],
            check=True,
        )
        subprocess.run([str(output_path)], check=True)


if __name__ == "__main__":
    main()
