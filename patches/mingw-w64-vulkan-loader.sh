# LICENSE.TXT path might not exist due to case-sensitive extraction
# Add a fallback in package() to find the license file regardless of case
sed -i 's|install -Dm644 "${srcdir}"/${_realname}-vulkan-sdk-${pkgver}/LICENSE.TXT|install -Dm644 "$(find "${srcdir}" -maxdepth 2 -iname LICENSE.TXT -print -quit)"|' PKGBUILD
