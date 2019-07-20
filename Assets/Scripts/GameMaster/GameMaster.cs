using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

public class GameMaster : MonoBehaviour
{
  static public Player player;
  static public Club enemyClub;
  static public FootballPlayer previousPlayer;
  static public Club previousBallHolder;
  static public Match currentMatch;

  void Awake(){
    if (player == null){
      player = new Player();
    }

    if (enemyClub == null){
      enemyClub = ClubFactory.newClub("EnemyClub", 8);
    }
  }

  public void finishMatch(){
    player.addCash(500);
    SceneManager.LoadScene("MainScene");
  }

  public void loadNextMatch(){
    currentMatch = new Match(player.getClub(),enemyClub);
    SceneManager.LoadScene("MatchScene");
  }

  public Player getPlayer(){
    return player;
  }

  public int getPlayerCash(){
    return player.getCash();
  }

  public Club getEnemyClub(){
    return enemyClub;
  }

  static public void nextMatchEvent(){
    currentMatch.nextMatchEvent();
  }
}
