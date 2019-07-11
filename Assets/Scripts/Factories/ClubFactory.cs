using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ClubFactory : MonoBehaviour
{
  FootballPlayerFactory footballPlayerFactory = new FootballPlayerFactory();

  public Club newClub(string _name = "El Rojo", int _powerMultiplier = 1){
    return new Club(_name, footballPlayerFactory.multipleNewFootballPlayers(11, _powerMultiplier));
  }

  public List<Club> multipleNewClubs(int ammount = 1){
    List<Club> clubs = new List<Club>();
    for(int i = 0; i < ammount; i++){
      clubs.Add(newClub());
    }
    return clubs;
  }
}
