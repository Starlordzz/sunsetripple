package host.msknet.sunsetripple.transport.nearby

data class NearbyEndpoint(
    val id: String,
    val name: String,
    val state: NearbyEndpointState = NearbyEndpointState.DISCOVERED,
)

enum class NearbyEndpointState { DISCOVERED, CONNECTING, CONNECTED }
