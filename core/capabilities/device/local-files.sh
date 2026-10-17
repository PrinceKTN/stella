#!/data/data/com.termux/files/usr/bin/bash

STELLA_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
question="$*"

# SHOW STELLA FOLDER
if echo "$question" | grep -Eiq \
    'show.*stella folder|stella folder|what.*in.*stella folder|files.*in.*stella folder'; then

    echo "📁 Stella folder: $STELLA_ROOT"
    echo

    find "$STELLA_ROOT" -maxdepth 1 -mindepth 1 \
        -printf '%f\n' 2>/dev/null | sort | sed 's/^/   /'

    exit 0
fi

# SHOW FILES
if echo "$question" | grep -Eiq \
    'what files.*here|list.*files|show.*files|files.*here'; then

    echo "📄 Files and folders in: $STELLA_ROOT"
    echo

    find "$STELLA_ROOT" -maxdepth 1 -mindepth 1 \
        -printf '%y  %f\n' 2>/dev/null | sort |
    while read -r TYPE NAME; do
        if [ "$TYPE" = "d" ]; then
            printf '   📁 %s/\n' "$NAME"
        else
            printf '   📄 %s\n' "$NAME"
        fi
    done

    exit 0
fi

# SHOW TREE
if echo "$question" | grep -Eiq \
    'show.*tree|folder.*tree|directory.*tree|tree.*stella'; then

    echo "🌳 Stella filesystem tree"
    echo

    if command -v tree >/dev/null 2>&1; then
        tree -L 2 "$STELLA_ROOT"
    else
        echo "   tree is not installed."
        echo "   Showing a safe two-level fallback:"
        find "$STELLA_ROOT" -maxdepth 2 -mindepth 1 \
            -printf '%p\n' 2>/dev/null | sort
    fi

    exit 0
fi

exit 2
