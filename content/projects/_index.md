{
  "title": "Projects",
  "summary": "Current research and selected past projects.",
  "type": "landing",
  "sections": [
    {
      "block": "markdown",
      "id": "projects-introduction",
      "content": {
        "title": "",
        "text": "# Projects"
      },
      "design": {
        "columns": "1"
      }
    },
    {
      "block": "collection",
      "id": "current-projects",
      "content": {
        "title": "## Current Project",
        "count": 0,
        "order": "desc",
        "filters": {
          "folders": [
            "projects"
          ],
          "featured_only": true
        }
      },
      "design": {
        "view": "date-title-summary",
        "show_date": false,
        "show_read_time": false,
        "show_read_more": false
      }
    },
    {
      "block": "collection",
      "id": "past-projects",
      "content": {
        "title": "## Selected Past Projects",
        "count": 0,
        "order": "desc",
        "filters": {
          "folders": [
            "projects"
          ],
          "exclude_featured": true
        }
      },
      "design": {
        "view": "date-title-summary",
        "show_date": false,
        "show_read_time": false,
        "show_read_more": false
      }
    }
  ]
}

