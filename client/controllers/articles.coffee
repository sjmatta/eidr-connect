Template.articles.helpers
  getSettings: ->
    fields = [
      {
        key: "url"
        label: "Title"
        fn: (value, object, key) ->
          return value
      },
      {
        key: "addedDate"
        label: "Added"
        fn: (value, object, key) ->
          return moment(value).fromNow()
      }
      {
        key: "publishDate"
        label: "Publication Date"
        fn: (value, object, key) ->
          return moment(value).format('MMM D, YYYY')
      }
    ]

    if Meteor.user()
      fields.push({
        key: "delete"
        label: ""
        cellClass: "remove-row"
      })

    fields.push({
      key: "expand"
      label: ""
      cellClass: "open-row-right"
    })

    return {
      id: 'event-sources-table'
      fields: fields
      showFilter: false
      showNavigationRowsPerPage: false
      showRowCount: false
      class: "table"
      filters: ["sourceFilter"]
    }

Template.articles.events
  "click .reactive-table tbody tr": (event, template) ->
    $target = $(event.target)
    $parentRow = $target.closest("tr")
    currentOpen = template.$("tr.tr-details")
    if $target.closest(".remove-row").length
      incidentCount = Incidents.find({userEventId: this.userEventId, url: this.url}).count()
      if incidentCount
        plural = if incidentCount is 1 then "" else "s"
        message = "There " +
          (if incidentCount is 1 then "is an incident report" else "are #{incidentCount} incident reports") +
          " associated with this article. Please delete the incident report#{plural} before deleting the article."
        toastr.error(message)
      else if window.confirm("Are you sure you want to delete this event source?")
        currentOpen.remove()
        Meteor.call("removeEventSource", @_id)
    else if not $parentRow.hasClass("tr-details")
      closeRow = $parentRow.hasClass("details-open")
      ###
      if currentOpen
        template.$("tr").removeClass("details-open")
        currentOpen.remove()
      if not closeRow
        #TODO: Display event source details.
      ###
  "click .open-source-form": (event, template) ->
    Modal.show("sourceModal", {userEventId: template.data.userEvent._id})

Template.articleSelect2.onRendered ->
  $input = @$("select")
  options = {}

  if @data.multiple
    options.multiple = true

  $input.select2(options)

  if @data.selected
    $input.val(@data.selected).trigger("change")
  $input.next(".select2-container").css("width", "100%")

Template.articleSelect2.onDestroyed ->
  templateInstance = Template.instance()
  templateInstance.$("#" + templateInstance.data.selectId).select2("destroy")
