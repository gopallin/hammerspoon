#!/usr/bin/env python3
import json
import os
import sys
import unittest
from datetime import datetime
from unittest.mock import patch, MagicMock

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import cat_gatekeeper

class TestCatGatekeeper(unittest.TestCase):
    def setUp(self):
        self.test_data_file = "/tmp/test_usage.json"
        cat_gatekeeper.DATA_FILE = self.test_data_file
        # Clear test data
        if os.path.exists(self.test_data_file):
            os.remove(self.test_data_file)

    def tearDown(self):
        if os.path.exists(self.test_data_file):
            os.remove(self.test_data_file)

    def test_load_empty_usage_data(self):
        """Test loading usage data when file doesn't exist."""
        data = cat_gatekeeper.load_usage_data()
        self.assertEqual(data, {})

    def test_save_and_load_usage_data(self):
        """Test saving and loading usage data."""
        test_data = {
            "2026-04-30": {
                "com.apple.Safari": {"duration": 1800, "name": "Safari"},
                "com.google.Chrome": {"duration": 900, "name": "Chrome"}
            }
        }
        cat_gatekeeper.save_usage_data(test_data)
        loaded = cat_gatekeeper.load_usage_data()
        self.assertEqual(loaded, test_data)

    def test_get_today_key(self):
        """Test date key format."""
        today = cat_gatekeeper.get_today_key()
        self.assertRegex(today, r"\d{4}-\d{2}-\d{2}")

    def test_daily_total_empty(self):
        """Test daily total when no data exists."""
        total = cat_gatekeeper.get_daily_total()
        self.assertEqual(total, 0)

    def test_daily_total_calculation(self):
        """Test daily total calculation."""
        today = cat_gatekeeper.get_today_key()
        test_data = {
            today: {
                "com.apple.Safari": {"duration": 1800, "name": "Safari"},
                "com.google.Chrome": {"duration": 900, "name": "Chrome"}
            }
        }
        cat_gatekeeper.save_usage_data(test_data)
        total = cat_gatekeeper.get_daily_total()
        self.assertEqual(total, 2700)  # 1800 + 900

    def test_is_limit_exceeded_false(self):
        """Test limit check when under limit."""
        today = cat_gatekeeper.get_today_key()
        test_data = {
            today: {
                "com.apple.Safari": {"duration": 3600, "name": "Safari"}  # 1 hour
            }
        }
        cat_gatekeeper.save_usage_data(test_data)
        cat_gatekeeper.DAILY_LIMIT = 14400  # 4 hours
        exceeded = cat_gatekeeper.is_limit_exceeded()
        self.assertFalse(exceeded)

    def test_is_limit_exceeded_true(self):
        """Test limit check when over limit."""
        today = cat_gatekeeper.get_today_key()
        test_data = {
            today: {
                "com.apple.Safari": {"duration": 14400, "name": "Safari"}  # 4 hours
            }
        }
        cat_gatekeeper.save_usage_data(test_data)
        cat_gatekeeper.DAILY_LIMIT = 14400  # 4 hours
        exceeded = cat_gatekeeper.is_limit_exceeded()
        self.assertTrue(exceeded)

    def test_update_usage_new_app(self):
        """Test adding usage for a new app."""
        cat_gatekeeper.update_usage("com.test.App", 600)
        data = cat_gatekeeper.load_usage_data()
        today = cat_gatekeeper.get_today_key()
        self.assertIn(today, data)
        self.assertIn("com.test.App", data[today])
        self.assertEqual(data[today]["com.test.App"]["duration"], 600)

    def test_update_usage_existing_app(self):
        """Test accumulating usage for an existing app."""
        cat_gatekeeper.update_usage("com.test.App", 600)
        cat_gatekeeper.update_usage("com.test.App", 300)
        data = cat_gatekeeper.load_usage_data()
        today = cat_gatekeeper.get_today_key()
        self.assertEqual(data[today]["com.test.App"]["duration"], 900)

    def test_get_status(self):
        """Test status reporting."""
        today = cat_gatekeeper.get_today_key()
        test_data = {
            today: {
                "com.apple.Safari": {"duration": 7200, "name": "Safari"}
            }
        }
        cat_gatekeeper.save_usage_data(test_data)
        cat_gatekeeper.DAILY_LIMIT = 14400
        status = cat_gatekeeper.get_status()

        self.assertEqual(status["total_seconds"], 7200)
        self.assertEqual(status["limit_seconds"], 14400)
        self.assertFalse(status["exceeded"])
        self.assertEqual(status["today"], today)

if __name__ == "__main__":
    unittest.main()
