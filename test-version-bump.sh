#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo "Testing Version Bump Script"
echo "======================================"
echo ""

# Test 1: Auto-bump when version matches tag
echo "TEST 1: Auto-bump patch when .version matches latest tag"
echo "Current .version: $(cat .version)"
echo "Latest tag: $(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
echo ""
echo "Running version-bump.sh..."
echo ""

bash .github/workflows/version-bump.sh

echo ""
echo "Result:"
echo "  .version now: $(cat .version)"
echo "  Latest tag now: $(git describe --tags --abbrev=0)"
echo ""

# Show all tags
echo "All tags (sorted):"
git tag --list | sort -V
echo ""

echo "======================================"
echo "Test completed successfully!"
echo "======================================"
