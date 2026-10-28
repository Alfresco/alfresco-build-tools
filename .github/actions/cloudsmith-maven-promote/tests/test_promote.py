import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import promote  # noqa: E402


def package(name, **changes):
    return {
        "name": name,
        "slug_perm": name,
        "format": "maven",
        "version": "9.1.0",
        "is_sync_completed": True,
        "is_downloadable": True,
        **changes,
    }


class PromotionTest(unittest.TestCase):
    def test_paginates_with_exact_group_and_version(self):
        api = promote.Cloudsmith("hyland", "test-token")
        api.request = Mock(
            side_effect=[
                ([package("parent")], {"X-Pagination-PageTotal": "2"}),
                ([package("engine")], {"X-Pagination-PageTotal": "2"}),
            ]
        )
        self.assertEqual(len(api.packages("staging", "org.activiti", "9.1.0")), 2)
        calls = api.request.call_args_list
        self.assertEqual(
            calls[0].kwargs["params"]["query"], "format:maven AND maven_group_id:^org.activiti$ AND version:^9.1.0$"
        )
        self.assertEqual(calls[1].kwargs["params"]["page"], 2)

    def test_rejects_wrong_version_in_api_response(self):
        api = promote.Cloudsmith("hyland", "test-token")
        api.request = Mock(return_value=([package("engine", version="9.1.0-alpha.1")], {}))
        with self.assertRaisesRegex(RuntimeError, "outside"):
            api.packages("staging", "org.activiti", "9.1.0")

    def test_moves_all_packages_and_waits_for_destination(self):
        api = Mock()
        first, second = package("parent"), package("engine")
        api.packages.side_effect = [[first, second], [], [first, second]]
        promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
        self.assertEqual(api.move.call_count, 2)
        api.move.assert_any_call("staging", second, "releases")

    def test_resumes_partial_promotion(self):
        api = Mock()
        api.packages.side_effect = [[package("engine")], [package("parent")], [package("parent"), package("engine")]]
        promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
        self.assertEqual(api.move.call_count, 1)

    def test_already_promoted_is_idempotent(self):
        api = Mock()
        api.packages.side_effect = [[], [package("parent")], [package("parent")]]
        promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
        api.move.assert_not_called()

    def test_empty_release_cannot_succeed(self):
        api = Mock()
        api.packages.return_value = []
        with self.assertRaisesRegex(RuntimeError, "Timed out"):
            promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 0)
        api.move.assert_not_called()

    def test_quarantined_or_failed_package_cannot_be_promoted(self):
        for state in ("is_quarantined", "is_sync_failed"):
            api = Mock()
            api.packages.side_effect = [[package("engine", **{state: True})], []]
            with self.assertRaisesRegex(RuntimeError, "quarantined"):
                promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
            api.move.assert_not_called()

    def test_waits_for_processing_before_moving(self):
        api = Mock()
        engine = package("engine")
        api.packages.side_effect = [[package("engine", is_sync_completed=False)], [], [engine], [], [engine]]
        with patch.object(promote.time, "sleep"):
            promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
        api.move.assert_called_once()

    def test_destination_conflict_cannot_replace_immutable_release(self):
        api = Mock()
        api.packages.return_value = [package("engine")]
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)
        api.move.assert_not_called()

    def test_move_error_stops_promotion(self):
        api = Mock()
        api.packages.side_effect = [[package("engine")], []]
        api.move.side_effect = RuntimeError("permission denied")
        with self.assertRaisesRegex(RuntimeError, "permission denied"):
            promote.promote(api, "staging", "releases", "org.activiti", "9.1.0", 1)


if __name__ == "__main__":
    unittest.main()
