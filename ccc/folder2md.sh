for f in ../$1/*.*; do
  echo "## $f " >> $1.md
  echo "\`\`\`c" >> $1.md
  cat "$f" >> $1.md
  echo "\`\`\`" >> $1.md
done
