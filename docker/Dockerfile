#FROM trenpixster/elixir
FROM debian

RUN apt-get update
RUN apt-get -y install wget
RUN wget http://packages.erlang-solutions.com/debian/erlang_solutions.asc && apt-key add erlang_solutions.asc
RUN wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && dpkg -i erlang-solutions_1.0_all.deb
RUN apt-get update
RUN apt-get -y install esl-erlang elixir

EXPOSE 4369
