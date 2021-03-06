app = angular.module 'PDFRenderer', ['pdfAnnotations', 'pdfTextLayer']

console.log 'hello from Renderer'

app.factory 'PDFRenderer', ['$q', '$timeout', 'pdfAnnotations', 'pdfTextLayer', ($q, $timeout, pdfAnnotations, pdfTextLayer) ->

	class PDFRenderer
		@JOB_QUEUE_INTERVAL: 100

		constructor: (@url, @options) ->
			@scale = @options.scale || 1
			@document = $q.when(PDFJS.getDocument @url)
			@navigateFn = @options.navigateFn
			@resetState()

		resetState: () ->
			console.log 'reseting renderer state'
			@page = []
			@complete = []
			@timeout = []
			@renderTask = []
			@renderQueue = []
			@jobs = 0

		getNumPages: () ->
			@document.then (pdfDocument) ->
				pdfDocument.numPages

		getPage: (pageNum) ->
			# with promise caching
			return @page[pageNum] if @page[pageNum]?
			@page[pageNum] = @document.then (pdfDocument) ->
				pdfDocument.getPage(pageNum)

		getPdfViewport: (pageNum, scale) ->
			scale ?= @scale
			@document.then (pdfDocument) ->
				pdfDocument.getPage(pageNum).then (page) ->
					viewport = page.getViewport scale

		getDestinations: () ->
			@document.then (pdfDocument) ->
				pdfDocument.getDestinations()

		getPageIndex: (ref) ->
			@document.then (pdfDocument) ->
				pdfDocument.getPageIndex(ref).then (idx) ->
					idx

		getScale: () ->
			@scale

		setScale: (@scale) ->
			@resetState()

		pause: (element, pagenum) ->
			return if @complete[pagenum]
			@renderQueue = @renderQueue.filter (q) ->
				q.pagenum != pagenum
			@stopSpinner (element.canvas)

		triggerRenderQueue: () ->
			$timeout () =>
				@processRenderQueue()
			, @JOB_QUEUE_INTERVAL

		removeCompletedJob: (pagenum) ->
			# may need to clean up deferred object here
			delete @renderTask[pagenum]
			@jobs = @jobs - 1
			@triggerRenderQueue()

		renderPage: (element, pagenum) ->
			viewport = $q.defer()
			current = {
				'element': element
				'pagenum': pagenum
			}
			@renderQueue.push(current)
			@triggerRenderQueue()

		processRenderQueue: () ->
			return if @jobs > 0
			current = @renderQueue.pop()
			return unless current?
			[element, pagenum] = [current.element, current.pagenum]
			return if @complete[pagenum]
			return if @renderTask[pagenum]
			@jobs = @jobs + 1

			@addSpinner(element.canvas)

			pageLoad = @getPage(pagenum)

			@renderTask[pagenum] = pageLoad.then (pageObject) =>
				@doRender element, pagenum, pageObject

			@renderTask[pagenum].then () =>
				# complete
				@complete[pagenum] = true
				@removeCompletedJob pagenum
			, () =>
				# rejected
				@removeCompletedJob pagenum

		doRender: (element, pagenum, page) ->
			self = this
			scale = @scale

			if (not scale?)
				console.log 'scale is undefined, returning'
				return

			canvas = $('<canvas class="pdf-canvas-new"></canvas>')

			viewport = page.getViewport (scale)

			devicePixelRatio = window.devicePixelRatio || 1

			ctx = canvas[0].getContext '2d'
			backingStoreRatio = ctx.webkitBackingStorePixelRatio ||
				ctx.mozBackingStorePixelRatio ||
				ctx.msBackingStorePixelRatio ||
				ctx.oBackingStorePixelRatio ||
				ctx.backingStorePixelRatio || 1
			pixelRatio = devicePixelRatio / backingStoreRatio

			scaledWidth = (Math.floor(viewport.width) * pixelRatio) | 0
			scaledHeight = (Math.floor(viewport.height) * pixelRatio) | 0

			newWidth = Math.floor(viewport.width)
			newHeight = Math.floor(viewport.height)

			canvas[0].height = scaledHeight
			canvas[0].width = scaledWidth

			canvas.height(newHeight + 'px')
			canvas.width(newWidth + 'px')

			element.canvas[0].height = newHeight
			element.canvas[0].width = newWidth

			if pixelRatio != 1
				ctx.scale(pixelRatio, pixelRatio)

			textLayer = new pdfTextLayer({
				textLayerDiv: element.text[0]
				viewport: viewport
			})
			page.getTextContent().then (textContent) ->
				console.log 'text content is', textContent
				window.RENDER_DELAY = 0
				textLayer.setTextContent textContent

			annotationsLayer = new pdfAnnotations({
				annotations: element.annotations[0]
				viewport: viewport
				navigateFn: @navigateFn
			})
			page.getAnnotations().then (annotations) ->
				console.log 'annotations are', annotations
				window.RENDER_DELAY = 0
				annotationsLayer.setAnnotations annotations

			return @renderTask = page.render {
				canvasContext: ctx
				viewport: viewport
			}
			.then () ->
				element.canvas.replaceWith(canvas)
				canvas.removeClass('pdf-canvas-new')

		addSpinner: (element) ->
			element.css({position: 'relative'})
			h = element.parent().height()
			w = element.parent().width()
			size = Math.floor(0.5 * Math.min(h, w))
			spinner = $('<div style="position: absolute; top: 50%; left:50%; transform: translateX(-50%) translateY(50%);"><i class="fa fa-spinner fa-spin" style="color: #999"></i></div>')
			spinner.css({'font-size' : size + 'px'})
			element.append(spinner)

		stopSpinner: (element) ->
			element.find('.fa-spin').removeClass('fa-spin')

	]
