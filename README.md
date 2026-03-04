# argocd-jsonnet

A extension for `argocd-repo-server` that adds required tools for generating resource manifests using Jsonnet for ArgoCD.

The image is built using the `Dockerfile`. Tools included: `helm`, `jsonnet`, `jb`, `yq`. Once changed a CI should be triggered to update the image. `argocd-repo-server` should be restarted manually upon change.

## Installation

Concept documentation for this installation method ("custom tooling"), can be found here:<br/> https://argo-cd.readthedocs.io/en/stable/operator-manual/custom_tools

### Installation Manifests

Add the following to `argocd-repo-server` deployment manifest, You can do so by patching the deployemnt, pass values to ArgoCD chart, etc...:

```yaml
initContainers:
  - name: jsonnet
    image: ghcr.io/marxus/argocd-jsonnet:v1.0.0
    command: [cp, -rv, /jsonnet/., /jsonnet-volume]
    volumeMounts:
      - name: jsonnet
        mountPath: /jsonnet-volume
containers:
  - name: argocd-repo-server
    env:
      - name: ARGOCD_HELM_ALLOW_CONCURRENCY
        value: 'true'
    volumeMounts:
      - name: jsonnet
        mountPath: /jsonnet
      - name: jsonnet
        mountPath: /usr/local/bin/git
        subPath: gitshim
      - name: jsonnet
        mountPath: /usr/local/bin/helm
        subPath: helmshim
volumes:
  - name: jsonnet
    emptyDir: {}
```

### Additional Installation Manifests

Add a role and role binding to enable application querying, this is required if the `argocd-repo-server` service account doesn't have such permission from beforehand:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: jsonnet }
rules:
  - apiGroups: [argoproj.io]
    resources: [applications]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: jsonnet }
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jsonnet
subjects:
  - kind: ServiceAccount
    name: argocd-repo-server
    namespace: <ARGOCD_NAMESPACE>
```

## Operation

The stdout stream produced by `jsonnet main.jsonnet` will be used as the manifest for the ArgoCD application. Make sure the output is well formatted YAML - <b>don't forget the multidoc divider `---` when producing multiple resources</b>.

- acts as a wrapper around a real helm binary - real helm charts applications support is unchanged
- runs `jsonnet main.jsonnet` in the context of `argocd-repo-server` container
- reusing the same repo clone for all generation operations (that's how helm acts in ArgoCD)
- can leverge some performence optimizations offered by ArgoCD's helm implementation such as concurrent proccessing: https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/#monorepo-scaling-considerations
- only runs if explicitly stated
- have access to the tools added via the Dockerfile (mounted at `/jsonnet`)
- have access to the ENV vars as stated here: https://argo-cd.readthedocs.io/en/stable/user-guide/build-environment
- have access to ENV vars passed by the application manifest (prefixed `ARGOCD_ENV_`)


## Usage

Assuming our application is generated from this path: `make/argocd/great/again`

1. Add files to the repo:

    ```sh
    make/argocd/great/again
    \_ ...
    \_ ...
    \_ main.jsonnet      # the entrypoint
    \_ helpers.libsonnet  # optional library files
    \_ ...
    ```

2. Explicitly state the usage of `jsonnet` in your application manifest

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: test-app
    spec:
      project: myproject
      source:
        repoURL: https://github.com/Secful/gitops.git
        path: make/argocd/great/again
        helm:
          values: jsonnet
          parameters:         # optional env vars to pass
            - name: MY_VALUE  # can be accessed as "ARGOCD_ENV_MY_VALUE"
              value: '123'
      destination:
        server: https://my.k8s.server.endpoint
        namespace: dev1
    ```

## Technical Flow

preparing the repo:
1. new commit/hard refresh to the git repo
2. argo clone the repo/fetch new commit
3. argo checkout the commit
4. argo makes sure the working git state is clean (by doing `git clean`)
    - `gitshim` intercepts any `git` command, if it's clean it:
      1. resolves jsonnet-bundler (`jb`) dependencies — if a `jsonnetfile.*` exists, it installs vendor libs into a content-hashed cache under `/tmp` and hard-links them as `_vendor` so jsonnet can resolve imports without modifying the repo
      2. adds a `Chart.yaml` next to any `main.jsonnet` it finds so argo treats the directory as a helm app
    - otherwise, run regular git binary

handling the application:
1. argo runs tool detection* or uses the tool defined in the app manifest - decides if it's a `helm` app
2. argo runs `helm template . <args>...` command
    - `helmshim` intercepts any `helm` command, if it finds `main.jsonnet` and `jsonnet` is explicitly stated to be used, it prepares the build env vars and the app env vars and runs `jsonnet main.jsonnet`
    - otherwise, run regular helm binary

<b>reference:</b>

git clean:
```
the argocd-repo-server ensures that repository is in the clean state during the manifest generation using config management tools such as...
```
https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/#argocd-repo-server<br/>
https://github.com/argoproj/argo-cd/blob/a624c9084582f4662a9c6919cdf055000b09fad0/util/git/client.go#L489-L490

helm template:<br/>
```
Helm is only used to inflate charts with helm template. The lifecycle of the application is handled by Argo CD instead of Helm...
```
https://argo-cd.readthedocs.io/en/stable/user-guide/helm/<br/>
https://github.com/argoproj/argo-cd/blob/a624c9084582f4662a9c6919cdf055000b09fad0/util/helm/cmd.go#L334-L335

## Thoughts and Tips

this is actually the largest section of this README. it contains assorted bullet points

1. will the helmshim break? well. it can but unlikely. it just intercepts `helm template` calls (the only thing ArgoCD uses helm for), and ArgoCD docs states on how to bring your own helm binary if you wish. but a way to minimize the risk is one of two:

    - never update ArgoCD

    - update Argo more frequently so if it breaks at least we know why.

    further more, ArgoCD broke the entire plugin eco system when they moved cmp's to sidecars. this is the nature of open source projects. thats why they have 2.9K open issues. you can get insights about ArgoCD's internals just by reading the issues: https://github.com/argoproj/argo-cd/issues

2. if you choose not use the supplied `gitshim` just include a `Chart.yaml` alongside `main.jsonnet` in order to use `helmshim`

3. `helmshim` was designed to expose the same build env vars as ArgoCD's config management plugins, but runs in the `argocd-repo-server` container context.

4. do not change files in the repo during generation. this affects all concorrent and following generations. actually, try to avoid changing files in the repo on the fly unless you know what you're doing.

5. please enjoy and don't forget to compline that everything I did here is complex. well, if you'd look at the bigger picture and think about it you'll understand that we have more flexabilty and easier way to do what WE want regarding on how we structure our repo, not what the tools force us to do.<br/>
IMO this method have alot of upsides, with the only downside of being unorthodox, hence, require someone of a "learning" curve to maintain (not to use, usage is dead easy!).
