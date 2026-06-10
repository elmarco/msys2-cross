# WHY: No cross-compiled libedit/readline available for pcre2test interactive mode
# pcre2 wants libedit/readline for pcre2test, but we don't have a
# cross-compiled version. Disable it.
sed -i 's/--enable-pcre2test-libedit/--disable-pcre2test-libedit/' PKGBUILD
