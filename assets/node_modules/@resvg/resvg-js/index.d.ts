/// <reference types="node" />

export type ResvgRenderOptions = {
  font?: {
    loadSystemFonts?: boolean
    fontFiles?: string[]
    fontDirs?: string[]
    defaultFontFamily?: string
    defaultFontSize?: number
    serifFamily?: string
    sansSerifFamily?: string
    cursiveFamily?: string
    fantasyFamily?: string
    monospaceFamily?: string
  }
  dpi?: number
  languages?: string[]
  shapeRendering?:
    | 0 // optimizeSpeed
    | 1 // crispEdges
    | 2 // geometricPrecision
  textRendering?:
    | 0 // optimizeSpeed
    | 1 // optimizeLegibility
    | 2 // geometricPrecision'
  imageRendering?:
    | 0 // optimizeQuality
    | 1 // optimizeSpeed
  fitTo?:
    | { mode: 'original' }
    | { mode: 'width'; value: number }
    | { mode: 'height'; value: number }
    | { mode: 'zoom'; value: number }
  background?: string // Support CSS3 color, e.g. rgba(255, 255, 255, .8)
  crop?: {
    left: number
    top: number
    right?: number
    bottom?: number
  }
  logLevel?: 'off' | 'error' | 'warn' | 'info' | 'debug' | 'trace'
}
export class BBox {
  x: number
  y: number
  width: number
  height: number
}

export function renderAsync(
  svg: string | Buffer,
  options?: ResvgRenderOptions | null,
  signal?: AbortSignal | null,
): Promise<RenderedImage>
export class Resvg {
  constructor(svg: Buffer | string, options?: ResvgRenderOptions | null)
  toString(): string
  render(): RenderedImage
  /**
   * Calculate a maximum bounding box of all visible elements in this SVG.
   *
   * Note: path bounding box are approx values.
   */
  innerBBox(): BBox | undefined
  /**
   * Calculate a maximum bounding box of all visible elements in this SVG.
   * This will first apply transform.
   * Similar to `SVGGraphicsElement.getBBox()` DOM API.
   */
  getBBox(): BBox | undefined
  /**
   * Use a given `BBox` to crop the svg. Currently this method simply changes
   * the viewbox/size of the svg and do not move the elements for simplicity
   */
  cropByBBox(bbox: BBox): void

  imagesToResolve(): Array<string>
  resolveImage(href: string, buffer: Buffer): void

  /** Get the SVG width */
  get width(): number

  /** Get the SVG height */
  get height(): number
}
export class RenderedImage {
  /** Write the image data to Buffer */
  asPng(): Buffer

  /** Get the RGBA pixels of the image */
  get pixels(): Buffer

  /** Get the PNG width */
  get width(): number

  /** Get the PNG height */
  get height(): number
}
