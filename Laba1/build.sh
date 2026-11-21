#!/bin/sh
set -u

# 1. Проверка аргументов
usage() {
    echo "Usage: $0 <source-file>" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

srcfile=$1

if [ ! -f "$srcfile" ]; then
    echo "$0: '$srcfile' is not a regular file" >&2
    exit 1
fi

if [ ! -r "$srcfile" ]; then
    echo "$0: '$srcfile' is not readable" >&2
    exit 1
fi

# 2. Определение директории и имени файла

case "$srcfile" in
    /*)
        srcarg=$srcfile
        ;;
    *)
        srcarg=./$srcfile
        ;;
esac

case "$srcfile" in
    */*)
        srcdir=${srcfile%/*}
        [ -n "$srcdir" ] || srcdir=/
        ;;
    *)
        srcdir=.
        ;;
esac

srcbase=${srcfile##*/}

# 3. Поиск имени выходного файла

outname=$(
    awk '
    {
        if (match($0, /Output:[[:space:]]*[^[:space:]]+/)) {
            result = substr($0, RSTART, RLENGTH)
            sub(/^Output:[[:space:]]*/, "", result)
            print result
            exit
        }
    }
    ' "$srcarg"
) || {
    echo "$0: failed to read output filename" >&2
    exit 3
}

if [ -z "$outname" ]; then
    echo "$0: Output comment not found in '$srcfile'" >&2
    exit 3
fi

# Проверяем корректность имени выходного файла.
case "$outname" in
    */*|.|..)
        echo "$0: invalid output filename '$outname'" >&2
        exit 3
        ;;
esac

case "$outname" in
    *[!a-zA-Z0-9._-]*)
        echo "$0: invalid characters in output filename" >&2
        exit 3
        ;;
esac

if [ "$outname" = "$srcbase" ]; then
    echo "$0: output filename must differ from source filename" >&2
    exit 3
fi

# 4. Создание временной директории

tmpdir=$(mktemp -d) || {
    echo "$0: failed to create temporary directory" >&2
    exit 5
}

# 5. Очистка временной директории

cleanup() {
    result=$?
    trap - 0
    rm -rf "$tmpdir"
    exit "$result"
}

trap cleanup 0

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 141' PIPE
trap 'exit 143' TERM

# 6. Компиляция исходного файла

case "$srcbase" in

    *.c)
        if ! gcc -Wall -Wextra -O2 \
            -o "$tmpdir/$outname" \
            "$srcarg" 2>"$tmpdir/build.log"
        then
            cat "$tmpdir/build.log" >&2
            exit 2
        fi
        ;;

    *.cpp|*.cc|*.cxx)
        if ! g++ -Wall -Wextra -O2 \
            -o "$tmpdir/$outname" \
            "$srcarg" 2>"$tmpdir/build.log"
        then
            cat "$tmpdir/build.log" >&2
            exit 2
        fi
        ;;

    *.tex)
        if ! pdflatex -interaction=nonstopmode -halt-on-error \
            -output-directory "$tmpdir" \
            "$srcarg" >"$tmpdir/build.log" 2>&1
        then
            cat "$tmpdir/build.log" >&2
            exit 2
        fi

        texbase=${srcbase%.tex}

        if [ ! -s "$tmpdir/$texbase.pdf" ]; then
            cat "$tmpdir/build.log" >&2
            exit 2
        fi

        if [ "$texbase.pdf" != "$outname" ]; then
            mv "$tmpdir/$texbase.pdf" "$tmpdir/$outname"
        fi
        ;;

    *)
        echo "$0: unsupported source file type '$srcbase'" >&2
        exit 4
        ;;

esac

# 7. Копирование результата

if ! cp "$tmpdir/$outname" "$srcdir/$outname"; then
    echo "$0: failed to copy output file" >&2
    exit 6
fi

echo "Build successful: $srcdir/$outname"
