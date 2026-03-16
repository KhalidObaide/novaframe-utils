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

        // Replace page title: "Roundcube Webmail" -> "NovaFrame Mail"
        $content = preg_replace(
            "#<title>[^<]*</title>#",
            "<title>NovaFrame Mail</title>",
            $content
        );

        // Replace product name text in login page
        $content = str_replace("Roundcube Webmail", "NovaFrame Mail", $content);
        $content = str_replace("Welcome to Roundcube Webmail", "Welcome to NovaFrame Mail", $content);
        $content = str_replace("Welcome to NovaFrame Mail", "Welcome to NovaFrame Mail", $content);

        $args["content"] = $content;
        return $args;
    }
}
