using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ClubFactory : MonoBehaviour
{

  static public Club newClub(string _name = "El Rojo", int _powerMultiplier = 1){
    return new Club(_name,
                    FootballPlayerFactory.newFootballPlayer(NameGenerator.getFullName(), _powerMultiplier),
                    FootballPlayerFactory.multipleNewFootballPlayers(3, _powerMultiplier),
                    FootballPlayerFactory.multipleNewFootballPlayers(3, _powerMultiplier),
                    FootballPlayerFactory.multipleNewFootballPlayers(3, _powerMultiplier));
  }

  static public List<Club> multipleNewClubs(int ammount = 1){
    List<Club> clubs = new List<Club>();
    for(int i = 0; i < ammount; i++){
      clubs.Add(newClub());
    }
    return clubs;
  }
}
