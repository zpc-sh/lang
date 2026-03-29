#!/bin/bash
# 🧹 JULES POST-MORTEM: OBLITERATE COPILOT SEEPAGE
# This script deletes all branches containing 'copilot' and forces garbage collection.

echo "🚨 WARNING: This will aggressively delete all local branches matching '*copilot*'."
echo "Starting cleanup..."

# 1. Delete Local Branches (if they exist)
# Fix: use format string instead of parsing 'git branch' to avoid '*' asterisk glob expansion
LOCAL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -i 'copilot')
if [ -n "$LOCAL_BRANCHES" ]; then
    for branch in $LOCAL_BRANCHES; do
        echo "🗑️ Deleting local branch: $branch"
        git branch -D "$branch"
    done
else
    echo "✅ No local copilot branches found."
fi

# 2. Instruct user on remote branches
REMOTE_BRANCHES=$(git branch -r | grep -i 'origin/copilot' | sed 's/origin\///')
if [ -n "$REMOTE_BRANCHES" ]; then
    echo "🚨 WARNING: There are remote copilot branches. You must delete them manually or run:"
    for branch in $REMOTE_BRANCHES; do
        echo "   git push origin --delete \"$branch\""
    done
else
    echo "✅ No remote copilot branches found."
fi

# 3. Obliterate the orphaned blobs via aggressive garbage collection
echo "☢️ Running aggressive garbage collection to purge unreachable binary blobs..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo "🎉 Cleanup complete! Check repository size:"
du -sh .git
