#!/usr/bin/env bash

set -euo pipefail

# Configurable via environment variables
NAMESPACE="${KAVITA_NAMESPACE:-kavita}"
LABEL_SELECTOR="${KAVITA_LABEL:-app=kavita}"

usage() {
    echo "Usage:"
    echo "  Upload: $0 [upload] <collection> <path-to-local-file> [--name=\"custom-name.pdf\"]"
    echo "  Remove: $0 rm <collection> <book-name-or-file>"
    echo ""
    echo "Examples:"
    echo "  $0 sre ~/Downloads/site-reliability-engineering.pdf"
    echo "  $0 upload sre ~/Downloads/pki.pdf --name=\"bulletproof-pki.pdf\""
    echo "  $0 rm sre bulletproof-pki"
    echo "  $0 rm sre \"Bulletproof-TLS-&-PKI.pdf\""
    exit 1
}

# 1. Parse optional flags (--name)
CUSTOM_NAME=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --name=*)
            CUSTOM_NAME="${1#*=}"
            shift
            ;;
        --name)
            CUSTOM_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

if [ "$#" -lt 2 ]; then
    echo "Error: Insufficient arguments."
    usage
fi

# 2. Determine subcommand (defaults to 'upload')
COMMAND="upload"
case "$1" in
    rm|remove)
        COMMAND="rm"
        shift
        ;;
    upload)
        COMMAND="upload"
        shift
        ;;
    *)
        COMMAND="upload"
        ;;
esac

# 3. Dynamically locate the running Kavita pod
echo "🔍 Looking up Kavita pod in namespace '$NAMESPACE'..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$POD_NAME" ]; then
    echo "❌ Error: No running pod found matching label '$LABEL_SELECTOR' in namespace '$NAMESPACE'."
    exit 1
fi

echo "📦 Found Pod: $POD_NAME"

# Sanitize collection input (strip leading slash if provided)
COLLECTION_TYPE="${1#/}"

# Verify root collection directory exists in pod
echo "🔎 Verifying '/$COLLECTION_TYPE' exists in the pod..."
if ! kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -d "/$COLLECTION_TYPE" 2>/dev/null; then
    echo "❌ Error: Root collection directory '/$COLLECTION_TYPE' does not exist inside the pod."
    echo "   Please update your Helm chart values/templates to add this mount path first."
    exit 1
fi

# -----------------------------------------------------------------------------
# SUBCOMMAND: RM (REMOVE)
# -----------------------------------------------------------------------------
if [ "$COMMAND" = "rm" ]; then
    TARGET_INPUT="$2"
    BOOK_NAME="$(basename "${TARGET_INPUT%.*}")"
    TARGET_DIR="/$COLLECTION_TYPE/$BOOK_NAME"

    echo "🔎 Checking if '$TARGET_DIR' exists in pod..."
    if ! kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -e "$TARGET_DIR" 2>/dev/null; then
        echo "❌ Error: Target directory '$TARGET_DIR' does not exist in the pod."
        exit 1
    fi

    echo "🗑️ Removing book directory: $TARGET_DIR"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- rm -rf "$TARGET_DIR"

    echo ""
    echo "✅ Book successfully removed!"
    echo "   Removed: $TARGET_DIR"
    exit 0
fi

# -----------------------------------------------------------------------------
# SUBCOMMAND: UPLOAD
# -----------------------------------------------------------------------------
LOCAL_FILE="$2"

if [ ! -f "$LOCAL_FILE" ]; then
    echo "Error: Local file '$LOCAL_FILE' not found."
    exit 1
fi

# Determine destination filename and book folder name
if [ -n "$CUSTOM_NAME" ]; then
    if [[ "$CUSTOM_NAME" == *.* ]]; then
        FILENAME="$CUSTOM_NAME"
    else
        ORIG_EXT="${LOCAL_FILE##*.}"
        FILENAME="${CUSTOM_NAME}.${ORIG_EXT}"
    fi
    BOOK_NAME="${FILENAME%.*}"
else
    FILENAME=$(basename "$LOCAL_FILE")
    BOOK_NAME="${FILENAME%.*}"
fi

if command -v exiftool &> /dev/null && [[ "$FILENAME" == *.pdf ]]; then
    echo "🏷️ Stripping internal PDF metadata..."
    exiftool -all= -overwrite_original "$LOCAL_FILE" > /dev/null
fi

TARGET_DIR="/$COLLECTION_TYPE/$BOOK_NAME"
TARGET_FILE_PATH="$TARGET_DIR/$FILENAME"

echo "📁 Creating book directory: $TARGET_DIR"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mkdir -p "$TARGET_DIR"

echo "🚀 Copying file to pod..."
kubectl cp "$LOCAL_FILE" "$NAMESPACE/$POD_NAME:$TARGET_FILE_PATH"

echo ""
echo "✅ File successfully uploaded!"
echo "   Destination: $TARGET_FILE_PATH"
