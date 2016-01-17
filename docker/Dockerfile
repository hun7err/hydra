FROM trenpixster/elixir

RUN git init && git remote add origin https://github.com/hun7err/hydra.git
RUN git fetch
RUN git checkout -t origin/devel
RUN mix deps.get
RUN mix compile

EXPOSE 4369
