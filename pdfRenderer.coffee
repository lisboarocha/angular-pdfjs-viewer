app = angular.module 'PDFRenderer', ['pdfAnnotations']

app.factory 'PDFRenderer', ['$q', '$timeout', 'pdfAnnotations', ($q, $timeout, pdfAnnotations) ->
	PDFJS.disableAutoFetch = true
	class PDFRenderer
		constructor: (@url, @options) ->
			@scale = @options.scale || 1
			@document = $q.when(PDFJS.getDocument @url)
			@scope = @options.scope
			@resetState()

		resetState: () ->
			console.log 'reseting renderer state'
			@complete = []
			@pageLoader = []
			@timeout = []
			@renderTask = []
			@renderQueue = []
			@jobs = 0

		getNumPages: () ->
			@document.then (pdfDocument) ->
				pdfDocument.numPages

		getPdfPageSize: () ->
			@document.then (pdfDocument) ->
				pdfDocument.getPage(1).then (page) ->
					viewport = page.getViewport 1
					[viewport.height, viewport.width]

		getPdfViewport: (pageNum) ->
			@document.then (pdfDocument) ->
				pdfDocument.getPage(pageNum).then (page) ->
					viewport = page.getViewport 1

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

		renderPage: (element, pagenum) ->
			current = {
				'element': element
				'pagenum': pagenum
			}
			@renderQueue.push(current)
			$timeout () =>
				@processRenderQueue()
			, 100

		processRenderQueue: () ->
			self = this

			if @jobs > 0
				#console.log 'not starting any new jobs', @jobs
				return

			current = @renderQueue.pop()
			return unless current?
			[element, pagenum] = [current.element, current.pagenum]

			if @complete[pagenum]
				return
			if @renderTask[pagenum]
				return

			@jobs = @jobs + 1

			@addSpinner(element.canvas)

			@pageLoader[pagenum] = @document.then (pdfDocument) ->
				pdfDocument.getPage(pagenum)
			@renderTask[pagenum] = @pageLoader[pagenum].then (pageObject) =>
				@doRender element, pagenum, pageObject

			@renderTask[pagenum].then () =>
				# complete
				self.complete[pagenum] = true
				delete @renderTask[pagenum]
				delete @pageLoader[pagenum]
				@jobs = @jobs - 1
				$timeout ()=>
					@processRenderQueue()
				, 100
			, () =>
				# rejected
				delete @renderTask[pagenum]
				delete @pageLoader[pagenum]
				@jobs = @jobs - 1
				$timeout () =>
					@processRenderQueue()
				, 100

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

			if pixelRatio != 1
				ctx.scale(pixelRatio, pixelRatio)

			textLayer = new TextLayerBuilder({
				textLayerDiv: element.text[0]
				layoutDone: true
				viewport: viewport
			})
			page.getTextContent().then (textContent) ->
				console.log 'text content is', textContent
				window.RENDER_DELAY = 0
				textLayer.setTextContent textContent

			annotationsLayer = new pdfAnnotations({
				annotations: element.annotations[0]
				viewport: viewport
				navigateFn:  (ref) =>
					@scope.navigateTo = ref
					@scope.$apply()
			})
			page.getAnnotations().then (annotations) ->
				console.log 'annotations are', annotations
				window.RENDER_DELAY = 0
				annotationsLayer.setAnnotations annotations

			# highlightsLayer = new HighlightsLayerBuilder({
			#		textLayerDiv: element.text[0]
			#		layoutDone: true
			#		viewport: viewport
			# })
			# page.getHighlights().then (highlights) ->
			#		console.log 'highlights are', highlights
			#		window.RENDER_DELAY = 0
			#		highlightsLayer.setHighlights highlights

			return @renderTask = page.render {
				canvasContext: ctx
				viewport: viewport
			}
			.then () ->
				element.canvas.replaceWith(canvas)
				canvas.removeClass('pdf-canvas-new')

	]
