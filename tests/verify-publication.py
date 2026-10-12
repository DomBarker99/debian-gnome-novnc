#!/usr/bin/env python3
"""Verify GHCR manifest/config reads without any saved registry credentials."""
import hashlib
import json
import sys
import urllib.parse
import urllib.request

image = sys.argv[1]
assert image.startswith('ghcr.io/'), 'Only GHCR is used by this project'
repository, tag = image.removeprefix('ghcr.io/').rsplit(':', 1)
query = urllib.parse.urlencode({'service': 'ghcr.io', 'scope': f'repository:{repository}:pull'})
with urllib.request.urlopen(f'https://ghcr.io/token?{query}', timeout=30) as response:
    token = json.load(response)['token']

def fetch(path, accept):
    request = urllib.request.Request(
        f'https://ghcr.io/v2/{repository}/{path}',
        headers={'Authorization': f'Bearer {token}', 'Accept': accept},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read(), response.headers

body, headers = fetch(
    f'manifests/{tag}',
    'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json',
)
manifest = json.loads(body)
digest = headers['Docker-Content-Digest']
assert digest == 'sha256:' + hashlib.sha256(body).hexdigest()
config_body, _ = fetch(f'blobs/{manifest["config"]["digest"]}', 'application/octet-stream')
assert manifest['config']['digest'] == 'sha256:' + hashlib.sha256(config_body).hexdigest()
config = json.loads(config_body)
assert config['os'] == 'linux' and config['architecture'] == 'amd64'
assert config['config']['User'] == '1000:1000'
assert not any(value.startswith(('VNC_PASSWORD=', 'VNC_PASSWORD_FILE=')) for value in config['config']['Env'])
print(json.dumps({
    'image': image,
    'anonymous_manifest_and_config_access': True,
    'digest': digest,
    'compressed_layer_bytes': sum(layer['size'] for layer in manifest['layers']),
    'platform': 'linux/amd64',
    'desktop_user': config['config']['User'],
}, indent=2))
