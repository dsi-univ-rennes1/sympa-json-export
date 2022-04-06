# Producing a JSON representation of Sympa mailing list catalog

* [Sympa project](https://www.sympa.org/)
* [Zimbra project](https://www.zimbra.com/)

## Goal of this project

Exporting a hierarchical representation of a mailing list service to be consumed by a Zimbra plugin (Zimlet). This zimlet helps end users select target mailing lists while writing an email.

The `export_json.pl` script generates a JSON structure that may be published on a web server. The Zimbra server will frequently load this JSON file through an HTTP request. 

## Running `export_json.pl`

The `export_json.pl` should be installed on your Sympa server. The script should be run whenever new lists/categories are created.

`SYMPALIB` refers to the directory where Sympa libraries are installed.

**Note**: the code requires Sympa **6.2.42 or higher** to be installed.

Example:
```
export SYMPALIB=/home/sympa/bin
$SYMPALIB/export_json.pl --robot=lists.my.fqdn --visibility_as_email=anybody@my.fqdn > /var/www/html/fqdn_lists.json
$SYMPALIB/export_json.pl --robot lists.my.fqdn  --visibility_as_email anybody@my.fqdn --exclude_topics='ex_inscrits' --exclude_lists='^\d+.*\@' > /var/www/html/fqdn_lists.json
```

## Sympa mailing list settings

### List topics

Sympa provides a `topics` list parameter to organize mailing lists. `topics` is a multi-valued list parameter.

Example: `topics topic1/subtopic,topic2`

Topics can't have mure than 2 levels.

Topics are listes on `/wws/lists_categories` Sympa pages.

### Visibility authorisation scenarios

Sympa provides many parameters to define who can do what. For example: "who can send a message", "who can review list members", who can subscribe to a list". Among those are parameters defining "who can view list in the server catalg" and "who can view a topic on the Sympa homepage".

These parameters refer to a so-called "authorization scenario". Authorization scenarios are dynamically evaluated, with a context (user email address, IP address, etc) to give an autorization decision. Authorization scenarios can be fine-grained, granting access to a user and not her colleague.

Topics and mailing lists visibility rely on authorization scenarios.


## Implementation details

### JSON structure

The produced JSON file is composed of:
* a `root` node with a description and `children` nodes,
* `topic` nodes with a description and `children` nodes,
* `list` nodes with a description and `email` attributes,
* `children` nodes can either include `topic` nodes or `list` nodes.

Here is a simple example:
```json
{
  "type": "root",
  "description": "Listes de diffusion étudiants de l'Université de Rennes 1",
  "children": [
    {
      "type": "topic",
      "description": "Faculté de médecine",
      "children": [
        {
          "type": "topic",
          "description": "Inscrits 2021-2022",
          "children": [
            {
              "type": "list",
              "email": "med-doctorat-2122@listes.etudiant.univ-rennes1.fr",
              "description": "Faculté de médecine : tous les étudiants inscrits en Doctorat (inscrits 2021-2022) (19 membres)"
            },
            {
              "type": "list",
              "email": "med-m10103-2122@listes.etudiant.univ-rennes1.fr",
              "description": "CERTIFICAT DE CAPACITE D'ORTHOPTISTE ANNEE2 (inscrits 2021-2022) (20 membres)"
            },
            {
              "type": "list",
              "email": "med-m10104-2122@listes.etudiant.univ-rennes1.fr",
              "description": "CERTIFICAT DE CAPACITE D'ORTHOPTISTE ANNEE3 (inscrits 2021-2022) (18 membres)"
            }
          ]
        }
      ]
    },
    {
      "type": "topic",
      "description": "Université de Rennes 1",
      "children": [
        {
          "type": "topic",
          "description": "Listes institutionnelles",
          "children": [
            {
              "type": "list",
              "email": "ur1-etudiants@listes.etudiant.univ-rennes1.fr",
              "description": "Tous les étudiants inscrits à l'Université, année universitaire en cours (37751 membres)"
            }
          ]
        }
      ]
    },
    {
      "type": "topic",
      "description": "IUT de Rennes",
      "children": [
        {
          "type": "list",
          "email": "t20301pastel@listes.etudiant.univ-rennes1.fr",
          "description": "Liste correspondant au parcours PASTEL de la LP Mécatronique (13 membres)"
        }
      ]
    }
  ]
}
```

### Excluding private mailing lists

Since our JSON file is generated once and later used (by Zimbra server) for different end-users, we could not afford processing Sympa authorization rules to exclude private mailing lists.

The `export_json.pl` script provides a `--visibility_as_email` argument. The argument value is an email address, used to evaluate `visibility` authorization scenarios.


### Excluding mailing lists or topics

You can filter lists or topics, based on regular expressions using the `--exclude_topics` and `--exclude_lists` command-line arguments.

### Merging JSON files

You might want to export a merged version of the JSON files, to publish mailing lists from multiple vhosts. Here is the JQ command to run to merge JSON files under a common root element:
```jq -s ' {type: "root", description: "Université de Rennes 1", children: .} | (.children[].type="topic") | (.children[].description |= sub("Université de Rennes 1 - ";""))|.' test_pers.json test_etu.json > test_all.json
```
