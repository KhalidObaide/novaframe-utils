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

        // Replace page title
        $content = preg_replace(
            "#<title>[^<]*</title>#",
            "<title>NovaFrame Mail</title>",
            $content
        );

        // Replace product name text
        $content = str_replace("Roundcube Webmail", "NovaFrame Mail", $content);

        // Replace favicon with NovaFrame favicon (base64 to bypass .htaccess)
        $favicon_file = "/var/www/html/custom-assets/favicon.ico";
        if (file_exists($favicon_file)) {
            $favicon_data = "data:image/x-icon;base64," . base64_encode(file_get_contents($favicon_file));
            // Replace existing favicon link
            $content = preg_replace(
                '#<link[^>]*rel="shortcut icon"[^>]*>#',
                '<link rel="shortcut icon" href="' . $favicon_data . '">',
                $content
            );
        }

        $args["content"] = $content;
        return $args;
    }
}
