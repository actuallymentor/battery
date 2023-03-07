module.exports = function bake_logo( percentage, opacity=1 ) {

    const max_height = 12
    const min_y_position = 3.5

    const percentage_as_decimal = percentage / 100
    const current_height = max_height * percentage_as_decimal
    const current_y_position = min_y_position + ( max_height - current_height )

    return `
        <svg opacity="${ opacity }" width="100%" height="100%" viewBox="0 0 18 18" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xml:space="preserve" xmlns:serif="http://www.serif.com/" style="fill-rule:evenodd;clip-rule:evenodd;stroke-linejoin:round;stroke-miterlimit:2;">
            <rect id="content" ry="1.5" x="5.35" y="${ current_y_position }" height="${ current_height }" width="7.25" />
            <g id="logo" transform="matrix(0.0217545,0,0,0.018,-1.87723,0)">
                <g id="outline" transform="matrix(0.827417,0,0,1,86.2915,0)">
                    <path d="M425.004,69.815L348.927,69.815C265.548,69.815 197.855,137.509 197.855,220.888L197.855,818.743C197.855,902.122 265.548,969.815 348.927,969.815L651.073,969.815C734.452,969.815 802.145,902.122 802.145,818.743L802.145,220.888C802.145,137.509 734.452,69.815 651.073,69.815L574.996,69.815C574.999,69.711 575,69.606 575,69.5L575,44.5C575,37.601 569.399,32 562.5,32L437.5,32C430.601,32 425,37.601 425,44.5L425,69.5C425,69.606 425.001,69.711 425.004,69.815ZM771.931,230.965C771.931,155.924 711.007,95 635.965,95L364.035,95C288.993,95 228.069,155.924 228.069,230.965L228.069,809.035C228.069,884.076 288.993,945 364.035,945L635.965,945C711.007,945 771.931,884.076 771.931,809.035L771.931,230.965Z"/>
                </g>
            </g>
        </svg>
    `

}