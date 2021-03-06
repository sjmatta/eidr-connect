incidentReportSchema = require('/imports/schemas/incidentReport.coffee')
# A annotation's territory is the sentence containing it,
# and all the following sentences until the next annotation.
# Annotations in the same sentence are grouped.
getTerritories = (annotationsWithOffsets, sents) ->
  annotationIdx = 0
  sentStart = 0
  sentEnd = 0
  territories = []
  sents.forEach (sent) ->
    sentStart = sentEnd
    sentEnd = sentEnd + sent.length
    sentAnnotations = []
    while annotation = annotationsWithOffsets[annotationIdx]
      [aStart, aEnd] = annotation.textOffsets[0]
      if aStart > sentEnd
        break
      else
        sentAnnotations.push annotation
        annotationIdx++
    if sentAnnotations.length > 0
      territories.push
        annotations: sentAnnotations
        territoryStart: sentStart
        territoryEnd: sentEnd
    else if territories.length > 0
      territories[territories.length - 1].territoryEnd = sentEnd
  return territories

Template.suggestedIncidentsModal.onCreated ->
  @incidentCollection = new Meteor.Collection(null)
  @loading = new ReactiveVar(true)
  @content = new ReactiveVar("")
  Meteor.call("getArticleEnhancements", @data.article.url, (error, result) =>
    if error
      Modal.hide(@)
      toastr.error error.reason
      return
    geonameIds = result.keypoints
      .filter((k)->k.location)
      .map((k)->k.location.geonameid)
    new Promise((resolve, reject) =>
      if geonameIds.length == 0
        resolve([])
      else
        HTTP.get("https://geoname-lookup.eha.io/api/geonames", {
          params:
            ids: geonameIds
        }, (error, geonamesResult) =>
          if error
            toastr.error error.reason
            Modal.hide(@)
            reject()
          else
            resolve(geonamesResult.data.docs)
        )
    ).then((locations) =>
      geonamesById = {}
      locations.forEach (loc)->
        geonamesById[loc.id] =
          geonameId: loc.id
          name: loc.name
          displayName: loc.name
          subdivision: loc.admin1Name
          latitude: parseFloat(loc.latitude)
          longitude: parseFloat(loc.longitude)
          countryName: loc.countryName
      @loading.set(false)
      @content.set result.source.cleanContent.content
      sents = result.source.cleanContent.content.split(".")
      sents = sents.slice(0, -1).map((s)->s + ".").concat(sents.slice(-1))
      keypoints = result.keypoints
      locTerritories = getTerritories(keypoints.filter((keypoint)->keypoint.location), sents)
      dateTerritories = getTerritories(keypoints.filter((keypoint)->keypoint.time), sents)
      result.keypoints.forEach((keypoint) =>
        unless keypoint.count then return
        [kStart, kEnd] = keypoint.textOffsets[0]
        locationTerritory = _.find locTerritories, ({territoryStart, territoryEnd})->
          if kEnd <= territoryEnd and kStart >= territoryStart
            return true
        dateTerritory = _.find dateTerritories, ({territoryStart, territoryEnd})->
          if kEnd <= territoryEnd and kStart >= territoryStart
            return true
        incident =
          timeRange: {}
          locations: locationTerritory.annotations.map(({location})->geonamesById[location.geonameid])
        mostFromKeys = 0
        mostToKeys = 0
        dateTerritory.annotations.forEach (annotation)->
          time = annotation.time
          if not time.timeRange
            #console.log "No Timerange", annotation
            return
          fromTime = time.timeRange.begin
          if fromTime
            fromKeys = Object.keys(fromTime).length
            parsedDate = moment(fromTime)
            if fromKeys > mostFromKeys and parsedDate.isValid()
              incident.timeRange.start = parsedDate.toDate()
              mostFromKeys = fromKeys
          toTime = time.timeRange.end
          if toTime
            toKeys = Object.keys(toTime).length
            # Round up the to date
            parsedDate = moment(_.extend({hours:23, minutes: 59}, toTime))
            if toKeys > mostToKeys and parsedDate.isValid()
              incident.timeRange.end = parsedDate.toDate()
              mostToKeys = toKeys
        incident.dateTerritory = dateTerritory
        incident.locationTerritory = locationTerritory
        incident.countAnnotation = keypoint
        if keypoint.count.case
          incident.deaths = keypoint.count.number
        else if keypoint.count.death
          incident.cases = keypoint.count.number
        incident.url = [@data.article.url]
        @incidentCollection.insert(incident)
      )
    )
  )
Template.suggestedIncidentsModal.helpers
  incidents: ->
    Template.instance().incidentCollection.find()
  incidentsFound: ->
    Template.instance().incidentCollection.find().count() > 0
  loading: ->
    Template.instance().loading.get()
  annotatedContent: ->
    content = Template.instance().content.get()
    lastEnd = 0
    html = ""
    Template.instance().incidentCollection.find().map (incident)->
      [start, end] = incident.countAnnotation.textOffsets[0]
      html += (
        Handlebars._escape("#{content.slice(lastEnd, start)}") +
        """<span
          class='annotation#{if incident.accepted then " accepted" else ""}'
          data-incident-id='#{incident._id}'
        >#{Handlebars._escape(content.slice(start, end))}</span>"""
      )
      lastEnd = end
    html += Handlebars._escape("#{content.slice(lastEnd)}")
    new Spacebars.SafeString(html)

Template.suggestedIncidentsModal.events
  "click .annotation": (event, template) ->
    incident = template.incidentCollection.findOne($(event.target).data("incident-id"))
    Modal.show("suggestedIncidentModal", {
      articles: [template.data.article]
      userEventId: template.data.userEventId
      incidentCollection: template.incidentCollection
      incident: incident
    })
  "click #add-suggestions": (event, template) ->
    incidents = Template.instance().incidentCollection.find({accepted: true}).map (incident)->
      _.pick(incident, incidentReportSchema.objectKeys())
    Meteor.call "addIncidentReports", incidents, (err, result)->
      if err
        toastr.error err.reason
      else
        Modal.hide(template)
