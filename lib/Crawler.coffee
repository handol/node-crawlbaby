_ = require 'underscore'
async = require 'async'
urlModule = require 'url'

Page = require './Page'


class Crawler
  constructor: (@config) ->
    null


  crawlCategory: (categoryConfig, callback) ->
    page = new Page()

    page.httpHeaders = @httpHeaders  if @httpHeaders?

    page.loadUrl categoryConfig.entryUrl, (err) =>
      return callback err  if err?
      
      crawlFields page, page.$.root(), categoryConfig.fields, callback


  crawlSite: (siteConfig, callback) ->
    categoryKeys = _.keys siteConfig.categories

    async.map categoryKeys
    ,
      (categoryKey, callback) =>
        categoryConfig = siteConfig.categories[categoryKey]

        @crawlCategory categoryConfig, callback
    ,
      (err, results) ->
        return callback err  if err?

        resultMap = {}
        for result, index in results
          resultMap[categoryKeys[index]] = result

        callback null, resultMap


  crawl: (callback) ->
    @httpHeaders = @config.httpHeaders  if @config.httpHeaders?

    siteKeys = _.keys @config.sites

    async.map siteKeys
    ,
      (siteKey, callback) =>
        siteConfig = @config.sites[siteKey]

        @crawlSite siteConfig, callback
    ,
      (err, results) ->
        return callback err  if err?

        resultMap = {}
        for result, index in results
          resultMap[siteKeys[index]] = result
          
        callback null, resultMap



crawlNextPage = (page, parentTag, fields, nextPageSelector, eq, resultsMap, callback) ->
  crawlFields page, parentTag, fields, (err, results) ->
    return callback err  if err?

    for k, v of results
      resultsMap[k] = []  if not resultsMap[k]?

      if v?
        for item in v
          resultsMap[k].push item

    if typeof eq is 'number'
      eqNo = eq
    else if eq is 'first'
      eqNo = 0
    else if eq is 'last'
      eqNo = parentTag.find(nextPageSelector).length

    nextPageTags = parentTag.find(nextPageSelector).eq(eqNo)
    return callback null, resultsMap  if not nextPageTags? or nextPageTags.length is 0

    nextPageTag = nextPageTags

    if nextPageTags['0'].type is 'tag' and nextPageTags['0'].name isnt 'a'
      nextPageTags = nextPageTags.find('a')
      return callback null, resultsMap  if not nextPageTags? or nextPageTags.length is 0
      nextPageTag = nextPageTags.eq(0)

    return callback null, resultsMap  if not nextPageTag.attr('href')

    nextPageUrl = nextPageTag.attr('href')
    if nextPageUrl.indexOf('http') isnt 0
      nextPageUrl = urlModule.resolve page.url, nextPageUrl
    
    console.log nextPageUrl
    nextPage = new Page()
    
    nextPage.httpHeaders = page.httpHeaders

    nextPage.loadUrl nextPageUrl, (err) ->
      return callback err  if err?
      crawlNextPage nextPage, nextPage.$.root(), fields, nextPageSelector, eq, resultsMap, callback



crawlFields = (page, parentTag, fields, callback) ->
  fieldKeys = _.keys fields

  async.map fieldKeys
  ,
    (fieldKey, callback) ->
      field = fields[fieldKey]
      
      if field.selector is 'this'
        tags = parentTag
      else
        tags = parentTag.find(field.selector)
      
      eq = field.eq
      if eq?
        if typeof eq is 'number'
          eqNo = eq
        else if eq is 'first'
          eqNo = 0
        else if eq is 'last'
          eqNo = tags.length
        
        tags = tags.eq(eqNo)
      else
        eqNo = 0

      if field.type is 'count'
        return callback null, tags.length

      if not tags? or tags.length is 0
        switch field.type
          when 'nextPage'
            return crawlNextPage page, parentTag, field.fields, field.selector, eq, {}, callback
          when 'url'
            return callback null, page.url
          else
            return callback null, null

      async.map [0...tags.length]
      ,
        (tagIndex, callback) ->
          tag = tags.eq(tagIndex)

          switch field.type
            when 'nextPage'
              crawlNextPage page, parentTag, field.fields, field.selector, eq, {}, callback

            when 'page'
              return callback null, null  if not tag.attr('href')?

              newPageUrl = tag.attr('href')
              if newPageUrl.indexOf('http') isnt 0
                newPageUrl = urlModule.resolve page.url, newPageUrl
              
              console.log newPageUrl
              newPage = new Page()

              newPage.httpHeaders = page.httpHeaders

              newPage.loadUrl newPageUrl, (err) ->
                return callback err  if err?                
                crawlFields newPage, newPage.$.root(), field.fields, callback

            when 'tag'
              crawlFields page, tag, field.fields, callback
            when 'text'
              tag.find('br').replaceWith('\r\n')

              text = tag.text()
              if field.removeText?
                re = new RegExp field.removeText.pattern, field.removeText.flags
                text = text.replace re, ''
              if field.replaceText?
                re = new RegExp field.replaceText.pattern, field.replaceText.flags
                text = text.replace re, field.replaceText.replaceString
              
              callback null, text
            when 'link'
              callback null, tag.attr('href')
            when 'class'
              callback null, tag.attr('class')
            when 'id'
              callback null, tag.attr('id')
            when 'image'
              callback null, tag.attr('src')
            else
              callback null, tag.text()
      ,
        (err, results) ->
          return callback err  if err?

          if not results?
            callback null, null
          else if Array.isArray(results) and results.length is 1
            callback null, results[0]
          else
            callback null, results
  ,
    (err, results) ->
      return callback err  if err?

      resultMap = {}
      for result, index in results
        resultMap[fieldKeys[index]] = result
      callback null, resultMap



module.exports = Crawler
