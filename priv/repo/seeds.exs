# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Justone.Repo.insert!(%Justone.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Justone.Repo
alias Justone.Game.Word

# 100 Spanish words for Just One game
spanish_words = [
  # Animals
  "perro", "gato", "elefante", "tigre", "león", "jirafa", "mono", "oso", "caballo", "vaca",
  # Food
  "pizza", "hamburguesa", "helado", "chocolate", "manzana", "plátano", "naranja", "pan", "queso", "huevo",
  # Objects
  "teléfono", "computadora", "televisión", "libro", "reloj", "lámpara", "mesa", "silla", "cama", "espejo",
  # Places
  "playa", "montaña", "hospital", "escuela", "biblioteca", "museo", "parque", "aeropuerto", "estadio", "iglesia",
  # Transportation
  "avión", "barco", "tren", "bicicleta", "moto", "autobús", "taxi", "cohete", "submarino", "helicóptero",
  # Nature
  "árbol", "flor", "río", "lago", "sol", "luna", "estrella", "nube", "lluvia", "nieve",
  # Body
  "corazón", "cerebro", "mano", "ojo", "nariz", "boca", "oreja", "diente", "pie", "rodilla",
  # Professions
  "médico", "bombero", "policía", "maestro", "piloto", "astronauta", "chef", "artista", "músico", "detective",
  # Sports
  "fútbol", "baloncesto", "tenis", "natación", "boxeo", "golf", "surf", "esquí", "voleibol", "béisbol",
  # Other
  "fantasma", "dragón", "robot", "vampiro", "pirata", "dinosaurio", "castillo", "corona", "tesoro", "magia"
]

for word <- spanish_words do
  case Repo.get_by(Word, word: word, language: "es") do
    nil ->
      %Word{}
      |> Word.changeset(%{word: word, language: "es"})
      |> Repo.insert!()
      IO.puts("Inserted: #{word}")

    _existing ->
      IO.puts("Skipped (already exists): #{word}")
  end
end

IO.puts("\nSeeded #{length(spanish_words)} Spanish words!")
