<?php
class novaframe_theme extends rcube_plugin
{
    public function init()
    {
        $this->add_hook("render_page", array($this, "inject_assets"));
    }

    public function inject_assets($args)
    {
        $content = $args["content"];
        $is_login = strpos($content, 'id="login-form"') !== false;

        // 1. Inject Google Fonts (Inter)
        $fonts = '<link rel="preconnect" href="https://fonts.googleapis.com">'
            . '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
            . '<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">';
        $content = str_replace("</head>", $fonts . "\n</head>", $content);

        // 2. Inject custom CSS
        $css_file = "/var/www/html/custom-assets/novaframe.css";
        if (file_exists($css_file)) {
            $css = "<style>\n" . file_get_contents($css_file) . "\n</style>";
            $content = str_replace("</head>", $css . "\n</head>", $content);
        }

        // 3. Replace page title
        $content = preg_replace(
            "#<title>[^<]*</title>#",
            "<title>NovaFrame Mail</title>",
            $content
        );

        // 4. Add body class for targeting
        if (strpos($content, '<body class="') !== false) {
            $content = str_replace('<body class="', '<body class="novaframe-branded ', $content);
        } else {
            $content = str_replace("<body", '<body class="novaframe-branded"', $content);
        }

        // 5. On login page: inject tagline and use white logo
        if ($is_login) {
            $content = str_replace("</body>", '<script>document.addEventListener("DOMContentLoaded",function(){var f=document.getElementById("login-form");if(f){var d=document.createElement("div");d.className="nf-login-tagline";d.innerHTML="Secure email powered by <strong>NovaFrame</strong>";f.parentNode.insertBefore(d,f.nextSibling);}});</script>' . "\n</body>", $content);

            // Use white logo on login (dark background)
            $logo_file = "/var/www/html/custom-assets/logo-white.svg";
        } else {
            // Use dark logo elsewhere (light background)
            $logo_file = "/var/www/html/custom-assets/logo.svg";
        }

        // 6. Inject JS for branding removal and UI enhancements
        $js = <<<'JSEOF'
<script>
document.addEventListener("DOMContentLoaded", function() {
    // Remove Roundcube branding text
    var els = document.querySelectorAll("a[href*='roundcube.net'], a[href*='roundcube'], .version");
    for (var i = 0; i < els.length; i++) { els[i].style.display = "none"; }

    // Add compose button enhancement
    var composeBtn = document.querySelector(".toolbar a.compose");
    if (composeBtn) {
        composeBtn.setAttribute("data-nf-enhanced", "true");
    }

    // Add unread badge styling
    var unreadSpans = document.querySelectorAll(".unreadcount");
    for (var j = 0; j < unreadSpans.length; j++) {
        unreadSpans[j].setAttribute("data-nf-badge", "true");
    }
});
</script>
JSEOF;
        $content = str_replace("</body>", $js . "\n</body>", $content);

        // 7. Replace logo src with base64 data URI
        if (file_exists($logo_file)) {
            $logo_data = "data:image/svg+xml;base64," . base64_encode(file_get_contents($logo_file));
            $pattern = '#src="[^"]*logo[^"]*\.svg[^"]*"#';
            $replacement = 'src="' . $logo_data . '"';
            $content = preg_replace($pattern, $replacement, $content);
        }

        $args["content"] = $content;
        return $args;
    }
}
