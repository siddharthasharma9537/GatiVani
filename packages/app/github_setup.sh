#!/bin/bash

# 🎙️ GatiVani - Automated GitHub Repository Setup
# This script creates a GitHub repository and pushes all code

set -e  # Exit on error

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║         🎙️  GatiVani - GitHub Repository Setup                ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
# STEP 1: Check Prerequisites
# ============================================================
echo "📋 STEP 1: Checking prerequisites..."
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed. Please install Git first."
    echo "   Visit: https://git-scm.com/downloads"
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "⚠️  GitHub CLI not found. You have two options:"
    echo ""
    echo "   Option 1: Install GitHub CLI (recommended)"
    echo "   Visit: https://cli.github.com"
    echo ""
    echo "   Option 2: Use manual Git setup (see instructions below)"
    echo ""
    read -p "Install GitHub CLI? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Please install GitHub CLI and run this script again."
        exit 1
    fi
fi

echo "✅ Prerequisites checked"
echo ""

# ============================================================
# STEP 2: Get GitHub Credentials
# ============================================================
echo "🔐 STEP 2: GitHub Authentication"
echo ""

# Check if already authenticated
if gh auth status &> /dev/null; then
    echo "✅ Already authenticated with GitHub"
    GH_USER=$(gh api user -q '.login')
    echo "   Logged in as: @$GH_USER"
else
    echo "📝 Logging in to GitHub..."
    gh auth login
fi

echo ""

# ============================================================
# STEP 3: Get Repository Details
# ============================================================
echo "📝 STEP 3: Repository Configuration"
echo ""

# Get current username
GH_USER=$(gh api user -q '.login')

# Set default values
REPO_NAME="gativani-app"
REPO_DESCRIPTION="GatiVani - Newspaper Audio Companion for Daily Commuters"
REPO_URL="https://github.com/$GH_USER/$REPO_NAME"

echo "Repository Details:"
echo "  Username: $GH_USER"
echo "  Repository Name: $REPO_NAME"
echo "  Description: $REPO_DESCRIPTION"
echo "  URL: $REPO_URL"
echo ""

read -p "Continue with these settings? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

echo ""

# ============================================================
# STEP 4: Check if Repository Exists
# ============================================================
echo "🔍 STEP 4: Checking if repository exists..."
echo ""

if gh repo view "$GH_USER/$REPO_NAME" &> /dev/null; then
    echo "⚠️  Repository already exists!"
    echo "   URL: $REPO_URL"
    echo ""
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing repository..."
        gh repo delete "$GH_USER/$REPO_NAME" --confirm
        echo "✅ Repository deleted"
    else
        echo "Using existing repository"
    fi
else
    echo "✅ Repository doesn't exist, ready to create"
fi

echo ""

# ============================================================
# STEP 5: Create GitHub Repository
# ============================================================
echo "🆕 STEP 5: Creating GitHub Repository..."
echo ""

if ! gh repo view "$GH_USER/$REPO_NAME" &> /dev/null; then
    gh repo create "$REPO_NAME" \
        --public \
        --description="$REPO_DESCRIPTION" \
        --homepage="https://gativani.dev" \
        --source=. \
        --remote=origin \
        --push
    
    echo "✅ Repository created successfully!"
else
    echo "✅ Using existing repository"
fi

echo ""

# ============================================================
# STEP 6: Push Code to GitHub
# ============================================================
echo "📤 STEP 6: Pushing code to GitHub..."
echo ""

# Initialize git if needed
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git config user.name "$GH_USER"
    git config user.email "$(gh api user -q '.email')"
fi

# Add remote if not exists
if ! git remote get-url origin &> /dev/null; then
    git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git"
fi

# Add all files
echo "Adding files..."
git add -A

# Create initial commit if needed
if ! git diff --cached --quiet; then
    echo "Creating initial commit..."
    git commit -m "Initial commit: Complete GatiVani codebase

✨ Features:
- Flutter app (iOS, Android, Web)
- Node.js backend
- 16+ integrated services
- Complete design system
- Full documentation
- Test coverage
- CI/CD ready

📊 Statistics:
- 130+ files
- 4000+ lines of code
- 50+ dependencies
- 43+ permissions configured

🚀 Ready for production"
fi

# Set main branch
echo "Pushing to GitHub..."
git branch -M main
git push -u origin main

echo "✅ Code pushed successfully!"
echo ""

# ============================================================
# STEP 7: Verify Repository
# ============================================================
echo "✅ STEP 7: Verifying Repository..."
echo ""

# Get repository info
gh repo view "$GH_USER/$REPO_NAME" --json nameWithOwner,url,description,primaryLanguage

echo ""

# ============================================================
# STEP 8: Setup GitHub Features
# ============================================================
echo "⚙️  STEP 8: Configuring GitHub Features..."
echo ""

# Enable features
echo "Enabling GitHub features..."

# Enable discussions
gh api repos/"$GH_USER"/"$REPO_NAME" -X PATCH -f has_discussions=true > /dev/null

# Enable wiki
gh api repos/"$GH_USER"/"$REPO_NAME" -X PATCH -f has_wiki=true > /dev/null

# Enable projects
gh api repos/"$GH_USER"/"$REPO_NAME" -X PATCH -f has_projects=true > /dev/null

# Set branch protection
echo "Setting up branch protection..."
gh api repos/"$GH_USER"/"$REPO_NAME"/branches/main/protection \
    -X PUT \
    -f "required_pull_request_reviews={dismiss_stale_reviews:true,require_code_owner_reviews:false,required_approving_review_count:1}" \
    -f "required_status_checks={strict:true,contexts:[]}" \
    -f "enforce_admins=false" \
    -f "allow_force_pushes=false" \
    -f "allow_deletions=false" \
    > /dev/null

echo "✅ Features configured"
echo ""

# ============================================================
# STEP 9: Create GitHub Secrets (Manual)
# ============================================================
echo "🔐 STEP 9: Next Steps for Secrets"
echo ""
echo "To complete setup, add GitHub Secrets:"
echo ""
echo "1. Go to: https://github.com/$GH_USER/$REPO_NAME/settings/secrets/actions"
echo ""
echo "2. Add these secrets:"
echo "   - FIREBASE_PROJECT_ID"
echo "   - FIREBASE_API_KEY"
echo "   - ANTHROPIC_API_KEY"
echo "   - AWS_ACCESS_KEY_ID"
echo "   - AWS_SECRET_ACCESS_KEY"
echo "   - SARVAM_API_KEY"
echo ""
echo "3. See GITHUB_DEPLOYMENT_GUIDE.md for detailed instructions"
echo ""

# ============================================================
# STEP 10: Summary
# ============================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║              ✅  SETUP COMPLETE!                               ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Repository Information:"
echo "   📍 URL: https://github.com/$GH_USER/$REPO_NAME"
echo "   👤 Owner: $GH_USER"
echo "   📦 Repo: $REPO_NAME"
echo "   🌟 Status: Public Repository"
echo ""

echo "📋 What's Next:"
echo "   1. Visit: https://github.com/$GH_USER/$REPO_NAME"
echo "   2. Add GitHub Secrets (see instructions above)"
echo "   3. Enable GitHub Pages in Settings"
echo "   4. Create first release"
echo "   5. Share with community!"
echo ""

echo "📚 Documentation:"
echo "   - See GITHUB_REPO_STRUCTURE.md for codebase details"
echo "   - See GRAPHIFY_ARCHITECTURE.md for architecture"
echo "   - See GITHUB_DEPLOYMENT_GUIDE.md for complete setup"
echo ""

echo "🎉 Your GatiVani repository is live on GitHub!"
echo ""

# Open repository in browser (optional)
read -p "Open repository in browser? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    gh repo view "$GH_USER/$REPO_NAME" --web
fi

echo ""
echo "✨ Thank you for using GatiVani! 🎙️"
echo ""
