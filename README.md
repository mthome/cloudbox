# cloudbox
Michael's (and friends') cloud scripting toolbox

## getting started
1. clone or copy the kubernetes subdirectory
2. add it to your path.  for instance, I have a copy of cloudbox/kubernetes in my ${HOME}/.lib/kubernetes, so I added the following line to my .zshrc:
`export PATH=${HOME}/.lib/cloudbox/kubernetes:${PATH}`
3. authenticate to gcloud:
`$ gcloud auth login`
4. run the following to do an initial population of your database:
`$ kdb -i`
5. activate a cloud virtual environment with something like:
`$ kactivate qa`
6. your shell prompt will change to indicate that you are *connected* to the cluster in question and you can run commands in context:
`qa cde ~$ krsh browser`
7. run khelp for options